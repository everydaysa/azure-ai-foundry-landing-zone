# Unit tests for the network module. They run offline with a mocked provider,
# so no Azure login or cost is involved:
#   cd infra/modules/network && terraform init -backend=false && terraform test

mock_provider "azurerm" {}

variables {
  name_prefix         = "aifz-test"
  location            = "eastus2"
  resource_group_name = "rg-aifz-test"
  address_space       = "10.10.0.0/16"
}

run "subnets_are_carved_deterministically" {
  command = plan

  assert {
    condition     = azurerm_subnet.aks_nodes.address_prefixes[0] == "10.10.0.0/22"
    error_message = "AKS node subnet must be the first /22 of the VNet."
  }

  assert {
    condition     = azurerm_subnet.private_endpoints.address_prefixes[0] == "10.10.4.0/24"
    error_message = "Private Endpoint subnet must be 10.10.4.0/24."
  }
}

run "no_implicit_internet_egress" {
  command = plan

  assert {
    condition     = !azurerm_subnet.aks_nodes.default_outbound_access_enabled && !azurerm_subnet.private_endpoints.default_outbound_access_enabled
    error_message = "Default outbound access must be disabled on every subnet."
  }
}

run "nsgs_apply_to_private_endpoints" {
  command = plan

  assert {
    condition     = azurerm_subnet.private_endpoints.private_endpoint_network_policies == "Enabled"
    error_message = "private_endpoint_network_policies must be Enabled or the PE NSG is ignored."
  }
}

run "private_endpoints_only_accept_https_from_aks" {
  command = plan

  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.private_endpoints.security_rule :
      r.access == "Deny" || (r.protocol == "Tcp" && r.destination_port_range == "443" && toset(r.source_address_prefixes) == toset(["10.10.0.0/22"]))
    ])
    error_message = "The only Allow rule on the PE subnet must be tcp/443 from the AKS node subnet."
  }
}

run "extra_private_endpoint_sources_are_added" {
  command = plan

  variables {
    private_endpoint_allowed_sources = ["10.10.6.0/27"]
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.private_endpoints.security_rule :
      r.access == "Allow" && contains(r.source_address_prefixes, "10.10.6.0/27")
    ])
    error_message = "Extra allowed sources must appear in the PE allow rule."
  }
}

run "rejects_address_space_that_is_not_a_slash_16" {
  command = plan

  variables {
    address_space = "10.10.0.0/20"
  }

  expect_failures = [var.address_space]
}
