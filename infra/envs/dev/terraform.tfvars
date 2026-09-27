# ─── dev: small, cheap, torn down after the demo ──────────────────────────
environment   = "dev"
location      = "eastus2"
address_space = "10.10.0.0/16"

# Monitoring: short retention + a 1 GB/day cap so a noisy bug can't run up the bill.
log_retention_days = 30
log_daily_quota_gb = 1

# Key Vault: shortest recoverable window (purge protection is always on).
key_vault_soft_delete_days = 7

# AKS: no-SLA tier, 2-3 small nodes across zones.
aks_sku_tier       = "Free"
aks_node_vm_size   = "Standard_D2ds_v5"
aks_node_min_count = 2
aks_node_max_count = 3

# AI Foundry: GA model (retires Sep 2027), US data zone, 10K tokens/min.
# Quota checked 2026-09-27: DataZoneStandard gpt-5.4-mini, 100 of 200 used.
model_deployments = {
  chat = {
    model_name    = "gpt-5.4-mini"
    model_version = "2026-03-17"
    sku_name      = "DataZoneStandard"
    capacity      = 10
  }
}

tags = {
  owner       = "kenwulff"
  cost_center = "portfolio"
}
