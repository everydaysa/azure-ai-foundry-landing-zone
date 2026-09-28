# ──────────────────────────────────────────────────────────────────────────
# Azure AI Foundry Secure Landing Zone — single entry point for every task.
# Run `make` or `make help` to list targets. CI calls these same targets,
# so "works on my machine" and "works in the pipeline" are the same thing.
# ──────────────────────────────────────────────────────────────────────────
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ENV       ?= dev
ENV_DIR   := infra/envs/$(ENV)
TF_DIRS    = $(shell find infra -name '*.tf' -not -path '*/.terraform/*' -not -path '*/tests/*' -exec dirname {} \; | sort -u)
TEST_DIRS  = $(shell find infra/modules -name '*.tftest.hcl' -exec dirname {} \; | xargs -n1 dirname | sort -u)
IMAGE     ?= aifz-app
TAG       ?= local

# Remote state lives in the bootstrap storage account. CI passes its name as a
# variable; locally it is discovered with the Azure CLI (you must be logged in).
TFSTATE_RG              ?= rg-aifz-bootstrap
TFSTATE_STORAGE_ACCOUNT ?= $(shell az storage account list -g $(TFSTATE_RG) --query "[?starts_with(name,'staifztfstate')].name | [0]" -o tsv 2>/dev/null)

.PHONY: help
help: ## List available targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make <target> [ENV=dev|prod]\n\n"} \
	  /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ─── Local setup ──────────────────────────────────────────────────────────
.PHONY: hooks
hooks: ## Install pre-commit git hooks
	pre-commit install

# ─── Terraform quality ────────────────────────────────────────────────────
.PHONY: fmt
fmt: ## Format all Terraform files
	terraform fmt -recursive infra

.PHONY: fmt-check
fmt-check: ## Fail if any Terraform file is not formatted (CI)
	terraform fmt -recursive -check -diff infra

.PHONY: validate
validate: ## terraform validate every module/env (no backend, no Azure login)
	@for d in $(TF_DIRS); do \
	  echo "==> validate $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
	  terraform -chdir=$$d validate -no-color; \
	done

.PHONY: test
test: ## Run every module's offline unit tests (terraform test, mocked provider)
	@for d in $(TEST_DIRS); do \
	  echo "==> test $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
	  terraform -chdir=$$d test -no-color; \
	done

.PHONY: lint
lint: ## TFLint with the azurerm ruleset
	tflint --init --config=$(CURDIR)/.tflint.hcl
	tflint --recursive --config=$(CURDIR)/.tflint.hcl

# ─── Policy as code ───────────────────────────────────────────────────────
.PHONY: checkov
checkov: ## Static scan: Terraform + Kubernetes + Dockerfile (Checkov)
	checkov --config-file policy/checkov/.checkov.yaml

.PHONY: opa-test
opa-test: ## Unit-test the OPA/Rego policies
	opa test policy/opa -v

.PHONY: policy-k8s
policy-k8s: ## OPA rules on the rendered Kubernetes manifests for ENV
	scripts/opa-eval.sh k8s $(ENV)

.PHONY: policy-plan
policy-plan: ## OPA rules on the saved Terraform plan for ENV (run `make plan` first)
	scripts/opa-eval.sh plan $(ENV)

.PHONY: policy
policy: checkov opa-test policy-k8s ## Run all offline policy-as-code checks

# ─── Application ──────────────────────────────────────────────────────────
.PHONY: app-test
app-test: ## Lint and unit-test the FastAPI app
	cd app && ruff check . && python3 -m pytest -q

.PHONY: docker-build
docker-build: ## Build the app container image locally
	docker build -t $(IMAGE):$(TAG) app

# ─── Aggregate (what CI runs on every PR) ─────────────────────────────────
.PHONY: ci
ci: fmt-check validate test lint policy app-test ## Run every local check

# ─── Deploy (requires `az login`) ─────────────────────────────────────────
.PHONY: bootstrap
bootstrap: ## One-time: create remote state + GitHub OIDC identities
	terraform -chdir=infra/bootstrap init
	terraform -chdir=infra/bootstrap apply

.PHONY: preflight
preflight: ## Check Azure prerequisites (login, host encryption, state account)
	@az account show --query "{subscription:name, id:id}" -o table
	@state=$$(az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state -o tsv); \
	  echo "EncryptionAtHost feature: $$state"; [ "$$state" = "Registered" ] || { echo "Run: az feature register --namespace Microsoft.Compute --name EncryptionAtHost"; exit 1; }
	@[ -n "$(TFSTATE_STORAGE_ACCOUNT)" ] || { echo "State storage account not found in $(TFSTATE_RG) - run 'make bootstrap' first."; exit 1; }
	@echo "State storage account: $(TFSTATE_STORAGE_ACCOUNT)"

.PHONY: init
init: ## terraform init for ENV against the remote state backend
	@[ -n "$(TFSTATE_STORAGE_ACCOUNT)" ] || { echo "State storage account not found - run 'az login' and 'make bootstrap' first."; exit 1; }
	terraform -chdir=$(ENV_DIR) init -input=false -reconfigure \
	  -backend-config=backend.hcl \
	  -backend-config="storage_account_name=$(TFSTATE_STORAGE_ACCOUNT)"

.PHONY: plan
plan: init ## terraform plan for ENV (default dev)
	terraform -chdir=$(ENV_DIR) plan -input=false -out=tfplan

.PHONY: apply
apply: ## Apply the saved plan for ENV
	terraform -chdir=$(ENV_DIR) apply -input=false tfplan

.PHONY: deploy-app
deploy-app: ## Build, push (JIT firewall) and deploy the app to ENV via az aks command invoke
	scripts/deploy-app.sh $(ENV)

.PHONY: smoke-test
smoke-test: ## Run the in-cluster smoke test against ENV (/healthz /readyz /whoami /chat)
	scripts/smoke-test.sh $(ENV)

.PHONY: k8s-render
k8s-render: ## Render the ENV overlay locally (needs generated/*.env from a previous deploy-app)
	kubectl kustomize k8s/overlays/$(ENV)

.PHONY: output
output: ## Show ENV outputs (endpoints, names, identities - no secrets)
	terraform -chdir=$(ENV_DIR) output

.PHONY: destroy
destroy: init ## Tear down ENV (asks for confirmation)
	@read -p "Destroy ALL resources in '$(ENV)'? Type the env name to confirm: " c; \
	  [ "$$c" = "$(ENV)" ] || { echo "Aborted."; exit 1; }
	terraform -chdir=$(ENV_DIR) destroy -input=false
