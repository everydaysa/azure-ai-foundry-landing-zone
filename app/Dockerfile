# syntax=docker/dockerfile:1
# ─── Keyless FastAPI service - production image ───────────────────────────
# Multi-stage: build tools stay in the builder; the runtime image holds only
# the virtualenv and our source, runs as a non-root user, and works with a
# read-only root filesystem (enforced in the Kubernetes manifests, Step 12).
#
# Build for AKS nodes (amd64) - also from an Apple-silicon Mac:
#   docker buildx build --platform linux/amd64 -t aifz-app:local app/

ARG PYTHON_IMAGE=python:3.12-slim-bookworm

# ─── Stage 1: build the virtualenv ────────────────────────────────────────
FROM ${PYTHON_IMAGE} AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-compile -r /tmp/requirements.txt

# ─── Stage 2: runtime ─────────────────────────────────────────────────────
FROM ${PYTHON_IMAGE} AS runtime

LABEL org.opencontainers.image.title="aifz-app" \
      org.opencontainers.image.description="Keyless FastAPI service calling Azure AI Foundry with AKS workload identity" \
      org.opencontainers.image.source="https://github.com/everydaysa/azure-ai-foundry-landing-zone" \
      org.opencontainers.image.licenses="MIT"

# Patch OS packages at build time, then drop apt metadata.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*

# Fixed, non-root UID/GID (Kubernetes runAsNonRoot can verify a numeric UID).
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=10001:10001 src/ /app/src/

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH="/app/src" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
USER 10001:10001
EXPOSE 8080

# --factory: the app is built at startup (identity + telemetry wired then).
# No --reload, no debug, docs endpoints disabled in the app itself.
CMD ["uvicorn", "app.main:app", "--factory", "--host", "0.0.0.0", "--port", "8080", \
     "--no-server-header", "--timeout-graceful-shutdown", "20"]
