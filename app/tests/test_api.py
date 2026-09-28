"""API tests - no Azure, no network: identity and model are replaced by fakes."""

import base64
import json
import time

import httpx
import openai
import pytest
from azure.core.credentials import AccessToken
from azure.core.exceptions import ClientAuthenticationError
from fastapi.testclient import TestClient

from app.config import Settings
from app.foundry import ChatResult
from app.main import create_app


def _fake_jwt(claims: dict) -> str:
    def b64(data: dict) -> str:
        return base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip("=")

    return f"{b64({'alg': 'none'})}.{b64(claims)}.signature"


class FakeCredential:
    """Stands in for the workload identity."""

    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.scopes: list[str] = []

    def get_token(self, *scopes: str, **_: object) -> AccessToken:
        self.scopes.extend(scopes)
        if self.fail:
            raise ClientAuthenticationError("no federated token")
        token = _fake_jwt(
            {
                "appid": "client-123",
                "oid": "object-456",
                "tid": "tenant-789",
                "aud": "https://cognitiveservices.azure.com",
                "idtyp": "app",
            }
        )
        return AccessToken(token, int(time.time()) + 3600)


class FakeChat:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error
        self.prompts: list[str] = []

    def complete(self, prompt: str) -> ChatResult:
        self.prompts.append(prompt)
        if self.error:
            raise self.error
        return ChatResult(
            answer="Hello from the model.",
            model="gpt-5.4-mini",
            prompt_tokens=12,
            completion_tokens=7,
        )


def _openai_error(cls: type[openai.APIStatusError], status: int) -> openai.APIStatusError:
    request = httpx.Request("POST", "https://example.openai.azure.com/openai/v1/chat/completions")
    return cls("error", response=httpx.Response(status, request=request), body=None)


@pytest.fixture
def settings() -> Settings:
    return Settings(
        foundry_openai_endpoint="https://ais-test.openai.azure.com/",
        foundry_deployment="chat",
        max_prompt_chars=50,
        applicationinsights_connection_string="",
    )


def _client(settings: Settings, credential=None, chat=None) -> TestClient:
    return TestClient(create_app(settings, credential or FakeCredential(), chat or FakeChat()))


# ─── Probes ───────────────────────────────────────────────────────────────
def test_healthz_is_dependency_free(settings):
    assert _client(settings, FakeCredential(fail=True)).get("/healthz").json() == {"status": "ok"}


def test_readyz_requires_a_token_for_the_foundry_scope(settings):
    cred = FakeCredential()
    assert _client(settings, cred).get("/readyz").status_code == 200
    assert cred.scopes == ["https://cognitiveservices.azure.com/.default"]


def test_readyz_is_503_when_identity_is_not_wired(settings):
    assert _client(settings, FakeCredential(fail=True)).get("/readyz").status_code == 503


# ─── /whoami ──────────────────────────────────────────────────────────────
def test_whoami_returns_identity_facts_but_never_the_token(settings):
    body = _client(settings).get("/whoami").json()
    assert body["client_id"] == "client-123"
    assert body["tenant_id"] == "tenant-789"
    assert body["object_id"] == "object-456"
    assert "token" not in body and "access_token" not in body
    assert "signature" not in json.dumps(body)


def test_whoami_reports_workload_identity_when_federated_token_present(settings, monkeypatch):
    monkeypatch.setenv(
        "AZURE_FEDERATED_TOKEN_FILE", "/var/run/secrets/azure/tokens/azure-identity-token"
    )
    assert _client(settings).get("/whoami").json()["auth_method"] == "workload_identity"


# ─── /chat ────────────────────────────────────────────────────────────────
def test_chat_returns_answer_and_token_usage(settings):
    chat = FakeChat()
    resp = _client(settings, chat=chat).post("/chat", json={"prompt": "hi"})
    assert resp.status_code == 200
    assert resp.json() == {
        "answer": "Hello from the model.",
        "model": "gpt-5.4-mini",
        "deployment": "chat",
        "prompt_tokens": 12,
        "completion_tokens": 7,
    }
    assert chat.prompts == ["hi"]


def test_chat_rejects_empty_prompt(settings):
    assert _client(settings).post("/chat", json={"prompt": ""}).status_code == 422


def test_chat_rejects_oversized_prompt_before_calling_the_model(settings):
    chat = FakeChat()
    resp = _client(settings, chat=chat).post("/chat", json={"prompt": "x" * 51})
    assert resp.status_code == 413
    assert chat.prompts == []  # no tokens spent


@pytest.mark.parametrize(
    ("error", "status"),
    [
        (_openai_error(openai.RateLimitError, 429), 429),
        (_openai_error(openai.PermissionDeniedError, 403), 502),
        (_openai_error(openai.InternalServerError, 500), 502),
    ],
)
def test_chat_maps_model_errors_without_leaking_details(settings, error, status):
    resp = _client(settings, chat=FakeChat(error=error)).post("/chat", json={"prompt": "hi"})
    assert resp.status_code == status
    # Only fixed, generic messages leave the service - never upstream error bodies.
    assert resp.json()["detail"] in {
        "model rate limit, retry later",
        "model access denied",
        "model call failed",
    }


def test_chat_is_503_not_500_when_the_identity_cannot_get_a_token(settings):
    """Regression: found by the local smoke test - the token provider raises
    ClientAuthenticationError (not an OpenAI error) before any HTTP call."""
    chat = FakeChat(error=ClientAuthenticationError("no federated token"))
    resp = _client(settings, chat=chat).post("/chat", json={"prompt": "hi"})
    assert resp.status_code == 503
    assert resp.json()["detail"] == "identity not ready"


# ─── Keyless by construction ──────────────────────────────────────────────
def test_foundry_client_uses_entra_token_provider_not_a_static_key(settings):
    from app.foundry import FoundryChat

    cred = FakeCredential()
    client = FoundryChat(settings, cred)._client
    assert str(client.base_url) == "https://ais-test.openai.azure.com/openai/v1/"
    # The key slot holds a CALLABLE that asks the workload identity for a fresh
    # Entra token for the Cognitive Services scope - there is no static key.
    provider = client._api_key_provider
    assert callable(provider)
    assert provider().count(".") == 2  # a JWT from the credential
    assert cred.scopes == ["https://cognitiveservices.azure.com/.default"]


def test_telemetry_is_off_without_connection_string(settings):
    from app.telemetry import configure_telemetry

    assert configure_telemetry(settings, FakeCredential()) is False


def test_requests_are_traced_when_telemetry_is_on(settings, monkeypatch):
    # Regression: the distro's global FastAPI patch missed our early-imported
    # class, so AppRequests stayed empty in production. The app must be
    # instrumented explicitly.
    import app.main as main

    monkeypatch.setattr(main, "configure_telemetry", lambda *_: True)
    app = create_app(settings, FakeCredential(), FakeChat())
    assert getattr(app, "_is_instrumented_by_opentelemetry", False)


def test_requests_are_not_traced_when_telemetry_is_off(settings):
    app = create_app(settings, FakeCredential(), FakeChat())
    assert not getattr(app, "_is_instrumented_by_opentelemetry", False)
