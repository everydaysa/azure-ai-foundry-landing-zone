# Non-secret backend settings for dev. The storage account name is passed
# separately (-backend-config="storage_account_name=...").
resource_group_name = "rg-aifz-bootstrap"
container_name      = "tfstate"
key                 = "dev.tfstate"
use_azuread_auth    = true
