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
TF_DIRS    = $(shell find infra -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; | sort -u)
IMAGE     ?= aifz-app
TAG       ?= local

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

.PHONY: lint
lint: ## TFLint with the azurerm ruleset
	tflint --init --config=$(CURDIR)/.tflint.hcl
	tflint --recursive --config=$(CURDIR)/.tflint.hcl

# ─── Policy as code ───────────────────────────────────────────────────────
.PHONY: checkov
checkov: ## Static security scan of Terraform (Checkov)
	checkov -d infra --config-file policy/checkov/.checkov.yaml

.PHONY: opa-test
opa-test: ## Unit-test the OPA/Rego policies
	opa test policy/opa -v

.PHONY: policy
policy: checkov opa-test ## Run all policy-as-code checks

# ─── Application ──────────────────────────────────────────────────────────
.PHONY: app-test
app-test: ## Lint and unit-test the FastAPI app
	cd app && ruff check . && python3 -m pytest -q

.PHONY: docker-build
docker-build: ## Build the app container image locally
	docker build -t $(IMAGE):$(TAG) app

# ─── Aggregate (what CI runs on every PR) ─────────────────────────────────
.PHONY: ci
ci: fmt-check validate lint policy app-test ## Run every local check

# ─── Deploy (requires `az login`) ─────────────────────────────────────────
.PHONY: bootstrap
bootstrap: ## One-time: create remote state + GitHub OIDC identities
	terraform -chdir=infra/bootstrap init
	terraform -chdir=infra/bootstrap apply

.PHONY: plan
plan: ## terraform plan for ENV (default dev)
	terraform -chdir=$(ENV_DIR) init -input=false
	terraform -chdir=$(ENV_DIR) plan -input=false -out=tfplan

.PHONY: apply
apply: ## Apply the saved plan for ENV
	terraform -chdir=$(ENV_DIR) apply -input=false tfplan

.PHONY: destroy
destroy: ## Tear down ENV (asks for confirmation)
	@read -p "Destroy ALL resources in '$(ENV)'? Type the env name to confirm: " c; \
	  [ "$$c" = "$(ENV)" ] || { echo "Aborted."; exit 1; }
	terraform -chdir=$(ENV_DIR) destroy -input=false
