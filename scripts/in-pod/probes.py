"""Runs INSIDE the aifz-app pod (via kubectl exec): network security probes.

Each probe prints PASS/FAIL. They test what the pod must NOT be able to do
(steal the node identity, reach the internet on plain ports) and what it must
do privately (resolve the model endpoint to a private IP).
"""

import os
import socket
import urllib.parse
import urllib.request

host = urllib.parse.urlparse(os.environ["FOUNDRY_OPENAI_ENDPOINT"]).hostname


def report(ok: bool, name: str, detail: str) -> None:
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")


# 1. Private DNS: the model hostname must resolve to a private endpoint IP.
try:
    ip = socket.gethostbyname(host)
    report(ip.startswith("10."), "Foundry resolves privately", f"{host} -> {ip}")
except OSError as e:
    report(False, "Foundry resolves privately", type(e).__name__)

# 2. IMDS must be unreachable (otherwise the pod could borrow the node's identity).
try:
    urllib.request.urlopen(  # noqa: S310 - deliberate probe of a fixed URL
        urllib.request.Request(
            "http://169.254.169.254/metadata/instance?api-version=2021-02-01",
            headers={"Metadata": "true"},
        ),
        timeout=4,
    )
    report(False, "IMDS blocked", "169.254.169.254 answered - node identity is exposed")
except Exception as e:  # noqa: BLE001 - any failure to connect is the expected outcome
    report(True, "IMDS blocked", f"no route to 169.254.169.254 ({type(e).__name__})")

# 3. Only 443 is allowed out: plain HTTP to the internet must be blocked.
s = socket.socket()
s.settimeout(4)
try:
    s.connect(("1.1.1.1", 80))
    report(False, "Internet port 80 blocked", "1.1.1.1:80 reachable")
except OSError as e:
    detail = f"1.1.1.1:80 unreachable ({type(e).__name__})"
    report(True, "Internet port 80 blocked", detail)
finally:
    s.close()
