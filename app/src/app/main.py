"""HTTP API.

GET  /healthz  liveness  - the process is up (no dependencies checked)
GET  /readyz   readiness - the pod can obtain an Entra token (identity wired)
GET  /whoami   demo      - NON-secret facts about the identity the app uses
POST /chat     calls the Foundry model deployment with that identity
"""

import logging
from typing import Protocol

import openai
from azure.core.credentials import TokenCredential
from azure.core.exceptions import ClientAuthenticationError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app import __version__
from app.config import Settings, get_settings
from app.foundry import ChatResult, FoundryChat
from app.identity import build_credential, describe_identity
from app.telemetry import configure_telemetry, instrument_app

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("app")


class ChatBackend(Protocol):
    def complete(self, prompt: str) -> ChatResult: ...


class ChatRequest(BaseModel):
    prompt: str = Field(min_length=1, description="The user's question")


class ChatResponse(BaseModel):
    answer: str
    model: str
    deployment: str
    prompt_tokens: int
    completion_tokens: int


def create_app(
    settings: Settings | None = None,
    credential: TokenCredential | None = None,
    chat_backend: ChatBackend | None = None,
) -> FastAPI:
    """App factory - production wiring by default, fakes injected in tests."""
    settings = settings or get_settings()
    credential = credential or build_credential()

    telemetry_on = configure_telemetry(settings, credential)
    backend = chat_backend or FoundryChat(settings, credential)

    app = FastAPI(title="aifz-app", version=__version__, docs_url=None, redoc_url=None)
    if telemetry_on:
        instrument_app(app)

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz() -> dict[str, str]:
        try:
            credential.get_token(settings.foundry_token_scope)
        except ClientAuthenticationError as exc:
            log.warning("readiness: cannot obtain Entra token (%s)", type(exc).__name__)
            raise HTTPException(status_code=503, detail="identity not ready") from exc
        return {"status": "ready"}

    @app.get("/whoami")
    def whoami() -> dict:
        try:
            return describe_identity(credential, settings.foundry_token_scope)
        except ClientAuthenticationError as exc:
            raise HTTPException(status_code=503, detail="identity not ready") from exc

    @app.post("/chat", response_model=ChatResponse)
    def chat(req: ChatRequest) -> ChatResponse:
        if len(req.prompt) > settings.max_prompt_chars:
            raise HTTPException(status_code=413, detail="prompt too long")
        # Log sizes and outcomes only - never prompt or answer text (PHI/PII).
        log.info("chat request: prompt_chars=%d", len(req.prompt))
        try:
            result = backend.complete(req.prompt)
        except ClientAuthenticationError as exc:
            # Raised by the token provider BEFORE any HTTP call: identity not wired.
            log.error("model call skipped: cannot obtain Entra token")
            raise HTTPException(status_code=503, detail="identity not ready") from exc
        except openai.RateLimitError as exc:
            raise HTTPException(status_code=429, detail="model rate limit, retry later") from exc
        except openai.PermissionDeniedError as exc:
            log.error("model call denied: check RBAC / private network path")
            raise HTTPException(status_code=502, detail="model access denied") from exc
        except openai.APIError as exc:
            log.error("model call failed: %s", type(exc).__name__)
            raise HTTPException(status_code=502, detail="model call failed") from exc
        log.info(
            "chat ok: prompt_tokens=%d completion_tokens=%d",
            result.prompt_tokens,
            result.completion_tokens,
        )
        return ChatResponse(
            answer=result.answer,
            model=result.model,
            deployment=settings.foundry_deployment,
            prompt_tokens=result.prompt_tokens,
            completion_tokens=result.completion_tokens,
        )

    return app


def _lazy_app() -> FastAPI:
    return create_app()


# `uvicorn app.main:app --factory` builds the app at startup (not at import).
app = _lazy_app
