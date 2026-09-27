terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # The bootstrap is the chicken-and-egg layer: it CREATES the remote state
  # backend, so its own (tiny) state starts local. See README.md for the
  # optional one-command migration into the storage account it creates.
}
