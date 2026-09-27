# Offline unit tests (mocked provider - no Azure login, no cost):
#   cd infra/modules/private_dns && terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # VNet links validate that the zone ID is a real ARM ID, so give the mocked
  # zones a correctly shaped one (the mock would otherwise invent a random word).
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.example.azure.com"
    }
  }
}

variables {
  name_prefix         = "aifz-test"
  resource_group_name = "rg-aifz-test"
  virtual_network_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/virtualNetworks/vnet-aifz-test"
}

run "default_zones_cover_every_private_endpoint" {
  command = plan

  assert {
    condition = toset([for z in azurerm_private_dns_zone.this : z.name]) == toset([
      "privatelink.cognitiveservices.azure.com",
      "privatelink.openai.azure.com",
      "privatelink.services.ai.azure.com",
      "privatelink.vaultcore.azure.net",
      "privatelink.azurecr.io",
    ])
    error_message = "Missing a zone: all three AI Foundry zones plus Key Vault and ACR are required."
  }
}

run "every_zone_is_linked_for_resolution_only" {
  command = apply # mocked

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == length(azurerm_private_dns_zone.this)
    error_message = "Every zone needs a VNet link, or nothing in the VNet can resolve it."
  }

  assert {
    condition     = alltrue([for l in azurerm_private_dns_zone_virtual_network_link.this : l.registration_enabled == false])
    error_message = "Auto-registration must be off on privatelink zones."
  }

  assert {
    condition     = alltrue([for l in azurerm_private_dns_zone_virtual_network_link.this : l.virtual_network_id == var.virtual_network_id])
    error_message = "Links must point at the landing-zone VNet."
  }
}

run "extra_zones_are_added" {
  command = plan

  variables {
    extra_zones = { aks = "privatelink.eastus2.azmk8s.io" }
  }

  assert {
    condition     = azurerm_private_dns_zone.this["aks"].name == "privatelink.eastus2.azmk8s.io" && length(azurerm_private_dns_zone.this) == 6
    error_message = "extra_zones must be merged with the defaults."
  }
}

run "rejects_non_privatelink_zone" {
  command = plan

  variables {
    extra_zones = { corp = "corp.example.com" }
  }

  expect_failures = [var.extra_zones]
}

run "rejects_malformed_vnet_id" {
  command = plan

  variables {
    virtual_network_id = "vnet-aifz-test"
  }

  expect_failures = [var.virtual_network_id]
}
