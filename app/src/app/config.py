"""Settings come ONLY from environment variables - there is no secret among them.

In AKS they are set by the Deployment (endpoint, deployment name, limits) and by
the workload identity webhook (AZURE_CLIENT_ID, AZURE_TENANT_ID,
AZURE_FEDERATED_TOKEN_FILE), which the Azure SDK reads automatically.
"""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False, extra="ignore")

    # AI Foundry - where to send requests (an address, not a credential).
    foundry_openai_endpoint: str = Field(
        default="", description="e.g. https://ais-aifz-dev-xxxx.openai.azure.com/"
    )
    foundry_deployment: str = Field(default="chat", description="Model deployment name")

    # Entra ID scope for Azure AI / Cognitive Services data-plane tokens.
    foundry_token_scope: str = "https://cognitiveservices.azure.com/.default"  # noqa: S105 - public OAuth scope URL, not a secret

    # Guardrails on cost and payload size.
    max_prompt_chars: int = Field(default=4000, ge=1, le=32000)
    max_completion_tokens: int = Field(default=400, ge=16, le=4096)
    request_timeout_seconds: float = Field(default=30.0, gt=0)

    system_prompt: str = (
        "You are a concise assistant running on a secure Azure AI Foundry landing zone. "
        "Answer in at most five sentences."
    )

    # Telemetry - optional so the app and tests run without Azure.
    applicationinsights_connection_string: str = ""
    service_name: str = "aifz-app"

    @property
    def foundry_base_url(self) -> str:
        """Azure OpenAI v1 API: version-less, so no api-version to chase."""
        return self.foundry_openai_endpoint.rstrip("/") + "/openai/v1/"


@lru_cache
def get_settings() -> Settings:
    return Settings()
