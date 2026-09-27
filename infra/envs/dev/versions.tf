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

  # Partial backend configuration: the non-secret, environment-specific values
  # live in backend.hcl; the state storage account name is supplied at init
  # time (CI: repository variable; locally: discovered by the Makefile).
  backend "azurerm" {}
}
