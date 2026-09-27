# ─── prod: same composition, production settings (defined, not deployed) ──
environment   = "prod"
location      = "eastus2"
address_space = "10.20.0.0/16" # never overlaps dev, so the two can be peered

# Monitoring: 90-day retention, never capped (security logs must not be dropped).
log_retention_days = 90
log_daily_quota_gb = -1

# Key Vault: maximum recovery window.
key_vault_soft_delete_days = 90

# AKS: Standard tier (99.95% API SLA), 3-5 nodes.
aks_sku_tier       = "Standard"
aks_node_vm_size   = "Standard_D2ds_v5"
aks_node_min_count = 3
aks_node_max_count = 5

# AI Foundry: same pinned model, more throughput.
model_deployments = {
  chat = {
    model_name    = "gpt-5.4-mini"
    model_version = "2026-03-17"
    sku_name      = "DataZoneStandard"
    capacity      = 30
  }
}

tags = {
  owner       = "kenwulff"
  cost_center = "portfolio"
}
