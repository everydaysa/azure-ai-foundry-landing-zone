"""Calls the AI Foundry model deployment with an Entra ID token - no API key.

Foundry has local (key) auth DISABLED, so a key would be rejected even if one
leaked. The OpenAI client below is given a *token provider*: a function that
returns a fresh, short-lived Entra access token for the pod's workload
identity. The client calls it before each request; azure-identity caches and
refreshes the token.
"""

from dataclasses import dataclass

from azure.core.credentials import TokenCredential
from azure.identity import get_bearer_token_provider
from openai import OpenAI
from opentelemetry import trace

from app.config import Settings

tracer = trace.get_tracer(__name__)


@dataclass(frozen=True)
class ChatResult:
    answer: str
    model: str
    prompt_tokens: int
    completion_tokens: int


class FoundryChat:
    """Thin, testable wrapper around the model deployment."""

    def __init__(self, settings: Settings, credential: TokenCredential) -> None:
        self._settings = settings
        entra_token_provider = get_bearer_token_provider(credential, settings.foundry_token_scope)
        # Azure OpenAI v1 API. The `api_key` slot receives a CALLABLE that
        # returns an Entra token on every request - there is no static key.
        self._client = OpenAI(
            base_url=settings.foundry_base_url,
            api_key=entra_token_provider,
            timeout=settings.request_timeout_seconds,
            max_retries=2,
        )

    def complete(self, prompt: str) -> ChatResult:
        s = self._settings
        # GenAI semantic-convention attributes -> searchable in App Insights.
        # The prompt text itself is NOT recorded (it may contain PHI/PII).
        with tracer.start_as_current_span("chat " + s.foundry_deployment) as span:
            span.set_attribute("gen_ai.system", "az.ai.openai")
            span.set_attribute("gen_ai.operation.name", "chat")
            span.set_attribute("gen_ai.request.model", s.foundry_deployment)
            span.set_attribute("gen_ai.request.max_tokens", s.max_completion_tokens)
            span.set_attribute("app.prompt.chars", len(prompt))

            response = self._client.chat.completions.create(
                model=s.foundry_deployment,
                messages=[
                    {"role": "system", "content": s.system_prompt},
                    {"role": "user", "content": prompt},
                ],
                # gpt-5.x are reasoning models: they take max_completion_tokens
                # (covers reasoning + visible output), not max_tokens.
                max_completion_tokens=s.max_completion_tokens,
            )

            usage = response.usage
            prompt_tokens = usage.prompt_tokens if usage else 0
            completion_tokens = usage.completion_tokens if usage else 0
            span.set_attribute("gen_ai.response.model", response.model)
            span.set_attribute("gen_ai.usage.input_tokens", prompt_tokens)
            span.set_attribute("gen_ai.usage.output_tokens", completion_tokens)

            return ChatResult(
                answer=(response.choices[0].message.content or "").strip(),
                model=response.model,
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
            )
