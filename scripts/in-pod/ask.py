"""Runs INSIDE the aifz-app pod (via kubectl exec): POST /chat on localhost.

The prompt arrives base64-encoded in PROMPT_B64, so any characters (quotes,
newlines) survive the trip laptop -> Azure -> cluster -> pod unchanged.
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.request

prompt = base64.b64decode(os.environ["PROMPT_B64"]).decode("utf-8")
req = urllib.request.Request(
    "http://localhost:8080/chat",
    data=json.dumps({"prompt": prompt}).encode(),
    headers={"content-type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=90) as resp:  # noqa: S310 - fixed localhost URL
        d = json.load(resp)
except urllib.error.HTTPError as e:
    print(f"ERROR {e.code}: {e.read().decode(errors='replace')}")
    sys.exit(1)

print(d["answer"])
print(
    f"\n-- {d['model']} (deployment '{d['deployment']}') | "
    f"{d['prompt_tokens']} prompt + {d['completion_tokens']} completion tokens | "
    "auth: workload identity, path: private endpoint"
)
