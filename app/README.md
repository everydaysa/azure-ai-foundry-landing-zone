# App: keyless FastAPI service

A small API that runs in AKS and calls the AI Foundry model deployment **using only its workload identity**. There's no API key in the code, the config, the image, or the cluster.

```
Pod (ServiceAccount ai-app/foundry-app)
 ├─ DefaultAzureCredential ─▶ WorkloadIdentityCredential ─▶ Entra token for id-aifz-<env>-app
 ├─ POST /chat ─▶ OpenAI client (v1 API) ─▶ Foundry via Private Endpoint
 │               api_key slot = CALLABLE token provider (fresh Entra token per request)
 └─ OpenTelemetry ─▶ App Insights (Entra-authenticated) ─▶ central Log Analytics workspace
```

## Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness: the process is up (no dependencies) |
| `GET /readyz` | Readiness: the pod can obtain an Entra token, so the identity is wired. `503` otherwise |
| `GET /whoami` | Demo: **non-secret** identity facts (client id, object id, tenant, token expiry). The token itself is never returned or logged |
| `POST /chat` | `{"prompt": "…"}` → `{answer, model, deployment, prompt_tokens, completion_tokens}` |

## Security properties

| Property | How |
|---|---|
| No keys | `api_key=get_bearer_token_provider(credential, scope)`: a callable returning a short-lived Entra token. Foundry has local auth disabled, so a static key would be rejected anyway. |
| No config secrets | Settings come from env vars: endpoint, deployment name, limits. The workload identity webhook injects `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_FEDERATED_TOKEN_FILE`. |
| Privacy | Prompt and answer **text is never logged or traced**, only sizes and token counts (important for PHI/PII) |
| Safe errors | Upstream errors map to fixed messages (`429`, `502`, `503`); no provider error bodies leak to callers |
| Cost guardrails | `MAX_PROMPT_CHARS` (rejected **before** the model is called) and `MAX_COMPLETION_TOKENS` |
| Container | Multi-stage build, Python 3.12 slim, OS packages patched at build, **non-root UID 10001**, read-only-root-filesystem compatible, docs endpoints off |
| Telemetry auth | The exporter uses the same credential (Monitoring Metrics Publisher). A leaked connection string can't send data |

## Observability

The Azure Monitor OpenTelemetry distro auto-instruments FastAPI; health probes are excluded. Each model call gets its own span with **GenAI semantic-convention** attributes: `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`. Example KQL:

```kusto
AppDependencies
| where Name startswith "chat "
| extend inTok = toint(Properties["gen_ai.usage.input_tokens"]), outTok = toint(Properties["gen_ai.usage.output_tokens"])
| summarize calls = count(), p95_ms = percentile(DurationMs, 95), tokens = sum(inTok + outTok) by bin(TimeGenerated, 5m)
```

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `FOUNDRY_OPENAI_ENDPOINT` | — | `terraform output foundry_openai_endpoint` |
| `FOUNDRY_DEPLOYMENT` | `chat` | Model deployment name |
| `MAX_PROMPT_CHARS` | `4000` | Larger prompts get `413` |
| `MAX_COMPLETION_TOKENS` | `400` | gpt-5.x uses `max_completion_tokens` (covers reasoning + output) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | *(empty = telemetry off)* | Where to send telemetry; not a credential |

## Develop and test

```bash
cd app
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
ruff check . && ruff format --check .
pytest -q                               # 14 tests, no Azure needed
```

Run locally against Azure (your own `az login` identity; you need network access to the Private Endpoint and the *Cognitive Services OpenAI User* role, so this normally only works inside the VNet):

```bash
FOUNDRY_OPENAI_ENDPOINT=https://ais-aifz-dev-xxxx.openai.azure.com/ \
  PYTHONPATH=src uvicorn app.main:app --factory --port 8080
```

## Container

```bash
# AKS nodes are amd64. On an Apple-silicon Mac, build for that platform:
docker buildx build --platform linux/amd64 -t aifz-app:local app/
docker run --rm -p 8080:8080 aifz-app:local        # /healthz → 200, /readyz → 503 (no identity locally)
```

In CI (Step 14) the image is scanned, pushed to ACR through the just-in-time firewall rule, and deployed **by digest**.
