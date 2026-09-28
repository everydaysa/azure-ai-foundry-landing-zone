# Diagram as code: generates docs/images/architecture.svg (the labelled reference
# architecture). Edit the layout here, then run:
#   python3 docs/images/generate_architecture.py
W, H = 1700, 1040
out = []
def a(s): out.append(s)

FONT = "font-family=\"'Segoe UI', -apple-system, Helvetica, Arial, sans-serif\""
C = dict(ink="#1b1f24", sub="#57606a", line="#d0d7de",
         gh="#24292f", ghbg="#f6f8fa",
         entra="#0063b1", entrabg="#eef6fc",
         az="#0078d4", azbg="#fbfdff",
         rg="#5c2d91", rgbg="#fcfaff",
         net="#107c10", netbg="#f3faf3",
         aks="#326ce5", aksbg="#eef3fd",
         pe="#107c10", pebg="#e3f4e3",
         paas="#8661c5", paasbg="#f5f0fc",
         obs="#ca5010", obsbg="#fff4ec",
         sec="#b3261e", secbg="#fdecea",
         ci="#0b5cad", run="#107c10", tok="#8661c5", tel="#ca5010")

def esc(t): return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def box(x, y, w, h, stroke, fill, rx=10, dash=None, sw=1.5):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

def text(x, y, t, size=13, color=None, weight="normal", anchor="start", italic=False):
    st = ' font-style="italic"' if italic else ""
    a(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color or C["ink"]}" font-weight="{weight}" text-anchor="{anchor}"{st}>{esc(t)}</text>')

def header(x, y, w, title, color, sub=None):
    text(x + 12, y + 22, title, 15, color, "700")
    if sub: text(x + w - 12, y + 22, sub, 12, C["sub"], anchor="end")

def card(x, y, w, h, title, lines, stroke, fill, tsize=13):
    box(x, y, w, h, stroke, fill, rx=8)
    text(x + 10, y + 19, title, tsize, stroke, "700")
    for i, l in enumerate(lines):
        text(x + 10, y + 37 + i * 16, l, 11.5, C["ink"])

def chip(x, y, t, color, bg):
    w = 8 + len(t) * 7.1
    box(x, y, w, 24, color, bg, rx=12, sw=1.2)
    text(x + w / 2, y + 16.5, t, 12.5, color, "700", "middle")
    return w

def arrow(d, color, style="solid", width=2.2):
    dash = {"solid": "", "dash": ' stroke-dasharray="7 5"', "dot": ' stroke-dasharray="2 4"'}[style]
    mid = {C["ci"]: "ci", C["run"]: "run", C["tok"]: "tok", C["tel"]: "tel"}[color]
    a(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"{dash} marker-end="url(#m-{mid})" stroke-linecap="round" stroke-linejoin="round"/>')

def badge(x, y, n, color):
    a(f'<circle cx="{x}" cy="{y}" r="11" fill="{color}" stroke="#ffffff" stroke-width="2"/>')
    text(x, y + 4.5, str(n), 12.5, "#ffffff", "700", "middle")

def label(x, y, t, color, anchor="start"):
    w = len(t) * 6.4 + 10
    bx = x if anchor == "start" else x - w / 2 if anchor == "middle" else x - w
    a(f'<rect x="{bx}" y="{y - 13}" width="{w}" height="18" rx="4" fill="#ffffff" opacity="0.92"/>')
    text(bx + 5, y, t, 11.5, color, "600")

a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" {FONT} role="img" aria-labelledby="t d">')
a('<title id="t">Azure AI Foundry Secure Landing Zone - reference architecture</title>')
a('<desc id="d">GitHub Actions authenticates to Entra ID with OIDC; deploy identities manage the dev resource group; a private AKS cluster runs the app with a workload identity and reaches AI Foundry, Key Vault and ACR through Private Endpoints; all telemetry goes to one Log Analytics workspace.</desc>')
a('<defs>')
for k in ("ci", "run", "tok", "tel"):
    a(f'<marker id="m-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{C[k]}"/></marker>')
a('</defs>')
a(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#ffffff"/>')

# ─── Title ────────────────────────────────────────────────────────────────
text(24, 42, "Azure AI Foundry Secure Landing Zone", 24, C["ink"], "700")
text(24, 66, "Reference architecture · dev environment (prod: same layout, 10.20.0.0/16, Standard tier, zones 1-3)", 13.5, C["sub"])
cx = 860
for t, red in (("model API keys disabled", True), ("0 public PaaS endpoints", True), ("0 pipeline secrets", True), ("1 telemetry workspace", False)):
    cx += chip(cx, 30, t, C["sec"] if red else C["obs"], C["secbg"] if red else C["obsbg"]) + 10

# ─── GitHub ───────────────────────────────────────────────────────────────
box(20, 90, 290, 610, C["gh"], C["ghbg"], rx=12)
header(20, 90, 290, "GitHub", C["gh"])
text(32, 132, "everydaysa/azure-ai-foundry-landing-zone", 11.5, C["sub"])
wf = [("ci.yml", "every PR · no Azure access"),
      ("plan.yml", "every PR · read-only plan + OPA"),
      ("deploy-dev.yml", "merge to main · auto"),
      ("deploy-prod.yml", "manual · reviewer · fingerprint"),
      ("drift.yml", "nightly · live plan + OPA")]
for i, (n, d) in enumerate(wf):
    y = 150 + i * 52
    box(34, y, 262, 42, C["gh"], "#ffffff", rx=7, sw=1.1)
    text(46, y + 18, n, 13, C["gh"], "700")
    text(46, y + 34, d, 11.5, C["sub"])
card(34, 425, 262, 118, "Guardrails", [
    "Ruleset on main: PR only,",
    "  7 required checks, no force-push",
    "Environments: main only;",
    "  prod requires a reviewer",
    "Actions pinned to commit SHA"], C["gh"], "#ffffff")
card(34, 555, 262, 130, "Policy gates (shift left)", [
    "Checkov: Terraform · Kubernetes ·",
    "  Dockerfile · workflows",
    "OPA on the Terraform PLAN JSON",
    "OPA on RENDERED manifests",
    "15 rules · 43 unit tests",
    "gitleaks · actionlint · 38 module tests"], C["gh"], "#ffffff")

# ─── Entra ID ─────────────────────────────────────────────────────────────
box(350, 90, 260, 610, C["entra"], C["entrabg"], rx=12)
header(350, 90, 260, "Microsoft Entra ID", C["entra"])
card(362, 125, 236, 88, "Federated credentials", [
    "exact match on issuer + subject:",
    "repo:owner@id/repo@id:<context>",
    "system:serviceaccount:ai-app:…"], C["entra"], "#ffffff")
card(362, 225, 236, 64, "id-aifz-gh-plan", [
    "Reader · AKS Cluster User",
    "state lock · PRs + nightly drift"], C["entra"], "#ffffff")
card(362, 300, 236, 80, "id-aifz-gh-dev", [
    "Contributor · AcrPush · AKS Admin",
    "RBAC Admin limited by ABAC:",
    "7 roles, to service principals only"], C["entra"], "#ffffff")
card(362, 391, 236, 64, "id-aifz-gh-prod", [
    "same rights, prod RG only",
    "runs only after reviewer approval"], C["entra"], "#ffffff")
card(362, 470, 236, 96, "id-aifz-dev-app", [
    "workload identity of the app pod",
    "Cognitive Services OpenAI User",
    "Key Vault Secrets User",
    "Monitoring Metrics Publisher"], C["tok"], "#ffffff")
text(480, 600, "Every credential is a short-lived", 12, C["entra"], "600", "middle")
text(480, 617, "token. No usable secret to steal.", 12, C["entra"], "600", "middle")
text(480, 648, "Owner ≠ data plane: the subscription", 11.5, C["sub"], anchor="middle")
text(480, 664, "Owner gets PermissionDenied on", 11.5, C["sub"], anchor="middle")
text(480, 680, "the model. Only the app identity can call it.", 11.5, C["sub"], anchor="middle")

# ─── Azure subscription ───────────────────────────────────────────────────
box(645, 90, 1035, 900, C["az"], C["azbg"], rx=12)
header(645, 90, 1035, "Azure subscription · East US 2", C["az"])
card(662, 122, 300, 108, "rg-aifz-bootstrap (one-time, Owner)", [
    "Terraform state: Entra-only (keys off),",
    "versioned, soft delete, delete lock",
    "3 CI identities + federated credentials",
    "created once by a human, then never again"], C["rg"], C["rgbg"])
box(980, 122, 682, 108, C["sub"], "#fafbfc", rx=8, dash="6 4")
text(992, 142, "rg-aifz-prod (defined + plan-verified on every PR, not kept running)", 13, C["sub"], "700")
text(992, 162, "same modules and settings shape · 10.20.0.0/16 · AKS Standard tier (SLA) · zones 1-3", 11.5, C["sub"])
text(992, 178, "3-5 nodes · 30K tokens/min · 90-day logs, no cap · deploy: reviewer approves a plan fingerprint", 11.5, C["sub"])
text(992, 194, "OPA rule T7 blocks a prod plan that isn't Standard tier", 11.5, C["sec"], "600")

# resource group dev
box(662, 245, 1000, 732, C["rg"], C["rgbg"], rx=10)
header(662, 245, 1000, "rg-aifz-dev", C["rg"], "47 resources · every one tagged project / environment / managed_by")

# VNet
box(680, 285, 505, 420, C["net"], C["netbg"], rx=10)
header(680, 285, 505, "VNet 10.10.0.0/16", C["net"])

# AKS subnet
box(695, 320, 285, 370, C["net"], "#ffffff", rx=8, dash="5 3")
text(705, 338, "snet-aks-nodes 10.10.0.0/22", 12, C["net"], "700")
text(705, 353, "NSG: deny inbound from Internet", 11, C["sub"])
box(705, 362, 265, 64, C["aks"], C["aksbg"], rx=7)
text(715, 381, "Private AKS cluster", 13, C["aks"], "700")
text(715, 398, "API server private · local accounts off", 11.5, C["ink"])
text(715, 414, "Entra ID + Azure RBAC · Azure Policy", 11.5, C["ink"])
box(705, 436, 265, 150, C["aks"], "#ffffff", rx=7)
text(715, 455, "namespace ai-app  (PSA: restricted)", 12.5, C["aks"], "700")
box(715, 464, 245, 60, C["aks"], C["aksbg"], rx=6, sw=1)
text(725, 482, "aifz-app pods (FastAPI)", 12.5, C["ink"], "700")
text(725, 498, "non-root · read-only FS · drop ALL", 11, C["ink"])
text(725, 513, "image pinned by @sha256 digest", 11, C["ink"])
text(715, 541, "ServiceAccount foundry-app", 11.5, C["tok"], "600")
text(715, 557, "→ workload identity (no key mounted)", 11.5, C["tok"])
text(715, 575, "NetworkPolicy: default-deny · IMDS blocked", 11.5, C["sec"], "600")
box(705, 596, 265, 84, C["aks"], "#ffffff", rx=7)
text(715, 614, "Node pool (autoscale 2-3)", 12.5, C["aks"], "700")
text(715, 630, "AzureLinux · Standard_D2ds_v4", 11.5, C["ink"])
text(715, 646, "ephemeral OS · host encryption", 11.5, C["ink"])
text(715, 662, "Cilium overlay · no public IPs", 11.5, C["ink"])
text(715, 675, "kubelet identity: AcrPull", 10.5, C["sub"])

# PE subnet
box(1000, 320, 170, 370, C["net"], "#ffffff", rx=8, dash="5 3")
text(1010, 338, "snet-private-endpoints", 12, C["net"], "700")
text(1010, 353, "10.10.4.0/24", 12, C["net"], "700")
text(1010, 368, "NSG: 443 from AKS only", 11, C["sub"])
text(1010, 382, "no outbound", 11, C["sub"])
for (y, n) in ((392, "PE · AI Foundry"), (467, "PE · Key Vault"), (607, "PE · Container Reg.")):
    box(1012, y, 146, 50, C["pe"], C["pebg"], rx=7)
    text(1085, y + 21, n, 12, C["pe"], "700", "middle")
    text(1085, y + 38, "private IP 10.10.4.x", 11, C["ink"], anchor="middle")

# PaaS column
card(1265, 380, 382, 74, "Azure AI Foundry  ·  gpt-5.4-mini", [
    "local auth OFF (keys can't authenticate)",
    "public network OFF · outbound restricted"], C["paas"], C["paasbg"])
card(1265, 460, 382, 64, "Key Vault", [
    "RBAC only · purge protection · public OFF"], C["paas"], C["paasbg"])
card(1265, 598, 382, 68, "Container Registry (Premium)", [
    "deny-by-default · admin + anonymous OFF",
    "CI push through a just-in-time IP rule"], C["paas"], C["paasbg"])
card(1265, 530, 382, 60, "Private DNS · 5 privatelink zones", [
    "linked to the VNet: names resolve to PE IPs"], C["net"], C["netbg"])

# NAT
card(815, 722, 170, 76, "NAT Gateway", [
    "1 static egress IP",
    "443 → Entra, Monitor"], C["net"], C["netbg"])
# public internet note
text(1000, 748, "Internet egress is 443 only,", 11.5, C["sub"])
text(1000, 764, "to public addresses (private", 11.5, C["sub"])
text(1000, 780, "ranges and IMDS excluded).", 11.5, C["sub"])

# Observability
box(680, 840, 967, 125, C["obs"], C["obsbg"], rx=10)
text(694, 863, "Log Analytics workspace log-aifz-dev  +  App Insights (workspace-based)", 15, C["obs"], "700")
text(694, 885, "Entra-only ingestion (local auth OFF): a leaked connection string can't write or forge telemetry · dev: 30 days, 1 GB/day cap", 12, C["ink"])
text(694, 905, "App: AppRequests · AppTraces (OpenTelemetry)   Cluster: ContainerLogV2 · KubeEvents · AKSAuditAdmin (every API write)", 12, C["ink"])
text(694, 925, "Platform: AzureDiagnostics (Foundry, Key Vault) · ContainerRegistryLoginEvents / RepositoryEvents · AzureMetrics", 12, C["ink"])
text(694, 948, "One KQL query can put an app error, a pod event, an audit entry and a model call on the same timeline.", 12, C["obs"], "600")

# ─── Arrows ───────────────────────────────────────────────────────────────
# 1 GitHub -> Entra (OIDC)
arrow("M296,280 H325 V170 H360", C["ci"], "dash")
badge(325, 225, 1, C["ci"])
# 2 dev identity -> AKS / ARM (apply, JIT push, command invoke)
arrow("M598,340 H630 V394 H703", C["ci"], "dash")
badge(630, 367, 2, C["ci"])
# 3 identities -> state
arrow("M598,257 H622 V176 H660", C["ci"], "dash")
badge(622, 216, 3, C["ci"])
# 4 pod -> Entra token exchange (workload identity)
arrow("M713,494 H600", C["tok"], "solid")
badge(655, 494, 4, C["tok"])
label(612, 520, "token swap", C["tok"])
# 5 pod -> PE Foundry -> Foundry
arrow("M960,478 H986 V417 H1010", C["run"])
arrow("M1158,417 H1263", C["run"])
badge(1210, 417, 5, C["run"])
label(1163, 405, "HTTPS 443", C["run"])
# pod -> PE KV -> KV
arrow("M960,500 H1010", C["run"])
arrow("M1158,492 H1263", C["run"])
# 6 kubelet -> PE ACR -> ACR
arrow("M970,632 H1010", C["run"])
arrow("M1158,632 H1263", C["run"])
badge(1210, 632, 6, C["run"])
label(1163, 620, "by digest", C["run"])
# 7 nodes -> NAT
arrow("M900,680 V720", C["run"], "solid")
badge(920, 700, 7, C["run"])
# DNS link
arrow("M1263,560 H1180", C["net"] if False else C["run"], "dot", 1.6)
# 8 telemetry
arrow("M730,680 V838", C["tel"], "dot", 2.4)
badge(730, 760, 8, C["tel"])
arrow("M1647,417 H1668 V902 H1649", C["tel"], "dot", 2.4)
for y in (492, 632):
    a(f'<path d="M1647,{y} H1668" fill="none" stroke="{C["tel"]}" stroke-width="2.4" stroke-dasharray="2 4"/>')
badge(1668, 760, 8, C["tel"])

# ─── Legend ───────────────────────────────────────────────────────────────
box(20, 720, 590, 300, C["line"], "#ffffff", rx=12)
text(34, 745, "How to read it", 15, C["ink"], "700")
leg = [(C["ci"], "dash", "Pipeline / control plane (ARM)"),
       (C["tok"], "solid", "Identity token exchange"),
       (C["run"], "solid", "Runtime data path (private)"),
       (C["tel"], "dot", "Telemetry and diagnostics")]
for i, (col, st, t) in enumerate(leg):
    y = 768 + i * 22
    dash = {"solid": "", "dash": ' stroke-dasharray="7 5"', "dot": ' stroke-dasharray="2 4"'}[st]
    a(f'<path d="M36,{y} H80" stroke="{col}" stroke-width="2.4"{dash}/>')
    text(90, y + 4, t, 12, C["ink"])
steps = [(1, C["ci"], "GitHub job presents its OIDC token; Entra checks repo ID + context"),
         (2, C["ci"], "Deploy identity: plan → OPA → apply; JIT image push; kubectl via ARM"),
         (3, C["ci"], "Every Terraform run reads/locks state with an Entra token"),
         (4, C["tok"], "Pod swaps its projected SA token for an Entra token (no secret)"),
         (5, C["run"], "App → DNS → Private Endpoint → Foundry (keys disabled)"),
         (6, C["run"], "Nodes pull the image by digest over the ACR Private Endpoint"),
         (7, C["run"], "Only outbound: NAT, 443, to Entra ID and Azure Monitor"),
         (8, C["tel"], "App, cluster, audit, Foundry, KV, ACR → one workspace")]
for i, (n, col, t) in enumerate(steps):
    y = 868 + i * 18.5
    badge(44, y - 4, n, col)
    text(62, y, t, 11.8, C["ink"])
a('</svg>')
open(__import__('pathlib').Path(__file__).with_name('architecture.svg'), 'w', encoding='utf-8').write("\n".join(out) + "\n")
print("written")
