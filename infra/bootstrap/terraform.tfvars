# Non-secret settings for the one-time bootstrap. Safe to commit.
location     = "eastus2"
project      = "aifz"
environments = ["dev", "prod"]

github_owner = "everydaysa"
github_repo  = "azure-ai-foundry-landing-zone"

# Public numeric IDs (not secrets). GitHub puts them in this repo's OIDC subject:
#   repo:everydaysa@311760416/azure-ai-foundry-landing-zone@1391048636:<context>
github_owner_id = 311760416
github_repo_id  = 1391048636

tags = {
  owner = "kenwulff"
}
