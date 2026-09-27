# ─── Private DNS module: the "internal phone book" ────────────────────────
#
#   app asks: myfoundry.cognitiveservices.azure.com ?
#     └─ public CNAME ─▶ myfoundry.privatelink.cognitiveservices.azure.com
#          └─ zone below is LINKED to our VNet ─▶ A 10.x.4.y  (the Private Endpoint)
#
# This module creates the zones and the VNet links. The A records are written
# automatically by each Private Endpoint's `private_dns_zone_group` (Steps 6-8),
# so no IP address is ever hard-coded.

locals {
  all_zones = merge(var.zones, var.extra_zones)
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.all_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.all_zones

  name                = "link-${var.name_prefix}-${each.key}"
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id  = var.virtual_network_id

  # These zones hold Private Endpoint records only - VMs must never register
  # their hostnames into a privatelink zone.
  registration_enabled = false

  # "Default" = strict: if a privatelink name has no record here, resolution
  # fails instead of silently falling back to the public IP. A missing record
  # shows up as an obvious error, not as a mysterious 403 from a public endpoint.
  resolution_policy = "Default"

  tags = var.tags
}
