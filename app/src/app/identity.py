"""The app's Azure identity - a workload identity, never a secret.

How a pod gets a token (nothing here is stored anywhere):
  1. The workload identity webhook projects a short-lived Kubernetes token
     (signed by the cluster's OIDC issuer) into the pod and sets
     AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_FEDERATED_TOKEN_FILE.
  2. DefaultAzureCredential -> WorkloadIdentityCredential exchanges it with
     Entra ID for an access token of the app's managed identity.
  3. RBAC on each Azure resource decides what that identity may do.
"""

import base64
import json
import os
from datetime import UTC, datetime
from typing import Any

from azure.core.credentials import TokenCredential
from azure.identity import DefaultAzureCredential

# Claims that are safe to show: identifiers and timestamps, never the token.
_PUBLIC_CLAIMS = ("appid", "azp", "oid", "tid", "aud", "iss", "idtyp")


def build_credential() -> TokenCredential:
    """DefaultAzureCredential picks WorkloadIdentityCredential in AKS and the
    developer's `az login` locally - the same code in both places."""
    return DefaultAzureCredential(exclude_interactive_browser_credential=True)


def auth_method() -> str:
    if os.environ.get("AZURE_FEDERATED_TOKEN_FILE"):
        return "workload_identity"
    return "developer_or_other"


def _decode_jwt_payload(token: str) -> dict[str, Any]:
    """Read (NOT verify) the payload of a token we just received from Entra ID
    over TLS. Used only to report non-secret identifiers."""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload))
    except (IndexError, ValueError):
        return {}


def describe_identity(credential: TokenCredential, scope: str) -> dict[str, Any]:
    """Acquire a token and return ONLY public facts about the identity."""
    access_token = credential.get_token(scope)
    claims = _decode_jwt_payload(access_token.token)
    return {
        "auth_method": auth_method(),
        "client_id": claims.get("appid") or claims.get("azp"),
        "object_id": claims.get("oid"),
        "tenant_id": claims.get("tid"),
        "audience": claims.get("aud"),
        "identity_type": claims.get("idtyp"),
        "token_expires_utc": datetime.fromtimestamp(access_token.expires_on, UTC).isoformat(),
        "note": "The access token itself is never returned or logged.",
    }
