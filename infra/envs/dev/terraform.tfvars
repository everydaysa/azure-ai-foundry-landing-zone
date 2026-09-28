# ─── dev: small, cheap, torn down after the demo ──────────────────────────
environment   = "dev"
location      = "eastus2"
address_space = "10.10.0.0/16"

# Monitoring: short retention + a daily cap so a noisy bug can't run up the bill.
# Sized from measurement, not guesswork: idle dev ingests ~44 MB/hour (~1.05
# GB/day) after the Container Insights trim - mostly AKS lease-heartbeat audit
# rows (see docs/observability.md §3). A 1 GB cap would trip every day and drop
# the security audit and app traces for the rest of that day; 2 GB leaves ~2x
# headroom while still stopping a runaway bug.
log_retention_days = 30
log_daily_quota_gb = 2

# Key Vault: shortest recoverable window (purge protection is always on).
key_vault_soft_delete_days = 7

# AKS: no-SLA tier, 2-3 small nodes (regional - see note below).
aks_sku_tier = "Free"
# D2ds_v4: this subscription has 0 vCPU quota for the DDSv5 family in eastus2
# and 10 for DDSv4 (checked 2026-09-27). 2 vCPU + 75 GiB local temp disk, so
# ephemeral OS disks and host encryption work as designed.
aks_node_vm_size = "Standard_D2ds_v4"
# Regional placement: AKS rejected zonal placement for this subscription in
# eastus2 (AvailabilityZoneNotSupported) even though `az vm list-skus` lists
# zones 1-3 for the size. See ADR-0007. Set ["1","2","3"] to re-enable.
aks_availability_zones = []
aks_node_min_count     = 2
aks_node_max_count     = 3

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
