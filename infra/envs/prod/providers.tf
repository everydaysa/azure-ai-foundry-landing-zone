provider "azurerm" {
  # State and any data-plane storage calls use Entra ID, never account keys.
  storage_use_azuread = true

  features {
    key_vault {
      # Purge protection is on, so purging is impossible anyway - don't try.
      purge_soft_delete_on_destroy = false
      # On re-deploy, recover a soft-deleted vault instead of failing on the name.
      recover_soft_deleted_key_vaults = true
    }

    cognitive_account {
      # Foundry accounts are soft-deleted for 48h; purge on destroy so a
      # redeploy is never blocked.
      purge_soft_delete_on_destroy = true
    }

    log_analytics_workspace {
      # dev: purge on destroy for a clean teardown. prod: keep the 14-day
      # soft-delete window so logs can be recovered after an accident.
      permanently_delete_on_destroy = false
    }
  }
}
