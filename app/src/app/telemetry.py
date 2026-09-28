"""OpenTelemetry -> Azure Monitor (App Insights -> the central Log Analytics workspace).

App Insights has local auth DISABLED, so the connection string only says WHERE
to send data. The exporter authenticates with the SAME workload identity as the
rest of the app (role: Monitoring Metrics Publisher). A leaked connection string
cannot inject or spoof telemetry.
"""

import logging
import os

from azure.core.credentials import TokenCredential
from fastapi import FastAPI

from app.config import Settings

log = logging.getLogger("app")


def configure_telemetry(settings: Settings, credential: TokenCredential) -> bool:
    """Enable traces, metrics and logs export if a connection string is set.
    Returns False (telemetry off) for local runs and tests."""
    if not settings.applicationinsights_connection_string:
        log.info("telemetry disabled: no APPLICATIONINSIGHTS_CONNECTION_STRING")
        return False

    # Probes fire every few seconds - keep them out of the traces.
    os.environ.setdefault("OTEL_PYTHON_FASTAPI_EXCLUDED_URLS", "healthz,readyz")

    # Imported lazily so tests and local runs don't need the exporter at all.
    from azure.monitor.opentelemetry import configure_azure_monitor
    from opentelemetry.sdk.resources import Resource

    configure_azure_monitor(
        connection_string=settings.applicationinsights_connection_string,
        credential=credential,  # Entra-authenticated ingestion
        logger_name="app",  # only our logger is exported, not every library's
        resource=Resource.create({"service.name": settings.service_name}),
        enable_live_metrics=False,
    )
    log.info("telemetry enabled: exporting to Azure Monitor with Entra ID auth")
    return True


def instrument_app(app: FastAPI) -> None:
    """Trace every request to THIS app instance (-> AppRequests).

    The distro instruments FastAPI by swapping in a patched `fastapi.FastAPI`
    class. main.py imported the class before that swap happened, so without
    this call the app is NOT traced: logs still arrive, requests silently don't.
    Found by checking the docs against the live workspace (AppRequests was empty).
    """
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz")
    log.info("request tracing enabled for this FastAPI app")
