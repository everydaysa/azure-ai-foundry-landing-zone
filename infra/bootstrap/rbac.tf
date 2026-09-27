# ─── Who can do what ──────────────────────────────────────────────────────
#
#  Principal            Scope                     Role
#  ───────────────────  ────────────────────────  ─────────────────────────────────────────
#  gh-plan              rg-<p>-<env> (each)       Reader
#  gh-plan/dev/prod     tfstate container         Storage Blob Data Contributor (state lock)
#  gh-<env>             rg-<p>-<env>              Contributor
#  gh-<env>             rg-<p>-<env>              RBAC Administrator  ◀ ABAC-constrained
#  gh-<env>             rg-<p>-<env>              AcrPush (push app images)
#  gh-<env>             rg-<p>-<env>              AKS RBAC Cluster Admin (kubectl deploy)
#  operators (humans)   tfstate container         Storage Blob Data Contributor
#  operators (humans)   rg-<p>-<env> (each)       AKS RBAC Cluster Admin
#
# Nothing here is granted at subscription scope.

locals {
  # The identity running the bootstrap (you) is always an operator.
  operators = setunion(var.operator_object_ids, [data.azurerm_client_config.current.object_id])

  # Every identity that runs `terraform init/plan/apply` needs state-blob access.
  state_readers = merge(
    { for k, id in azurerm_user_assigned_identity.github : "ci-${k}" => { principal_id = id.principal_id, type = "ServicePrincipal" } },
    { for oid in local.operators : "op-${oid}" => { principal_id = oid, type = null } }
  )

  # Allow-list of role GUIDs for the ABAC condition below.
  assignable_role_guids = join(", ", sort([
    for r in data.azurerm_role_definition.assignable : basename(r.role_definition_id)
  ]))

  # Human-readable form of the condition:
  #   IF the action is "create a role assignment"
  #     THEN the role must be in the allow-list AND the assignee must be a
  #          service principal / managed identity (never a user or group).
  #   IF the action is "delete a role assignment"
  #     THEN the role being removed must be in the allow-list.
  rbac_admin_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_role_guids}}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_role_guids}}
     )
    )
  EOT
}

data "azurerm_role_definition" "assignable" {
  for_each = var.pipeline_assignable_roles
  name     = each.value
}

# ─── State access ─────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "state_blob" {
  for_each = local.state_readers

  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
  principal_type       = each.value.type
  description          = "Read/write Terraform state and hold the state lease (lock)."
}

# ─── Plan identity: read-only on every environment ────────────────────────
resource "azurerm_role_assignment" "plan_reader" {
  for_each = azurerm_resource_group.env

  scope                = each.value.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github["plan"].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Pull-request plans and drift detection are read-only."
}

# ─── Deploy identities: one environment each ──────────────────────────────
resource "azurerm_role_assignment" "deploy_contributor" {
  for_each = azurerm_resource_group.env

  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github[each.key].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Create and manage landing-zone resources in ${each.key} only."
}

resource "azurerm_role_assignment" "deploy_rbac_admin" {
  for_each = azurerm_resource_group.env

  scope                = each.value.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github[each.key].principal_id
  principal_type       = "ServicePrincipal"
  description          = "May assign ONLY allow-listed roles, ONLY to service principals / managed identities."
  condition_version    = "2.0"
  condition            = local.rbac_admin_condition
}

resource "azurerm_role_assignment" "deploy_acr_push" {
  for_each = azurerm_resource_group.env

  scope                = each.value.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github[each.key].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Push application images to the environment's registry."
}

resource "azurerm_role_assignment" "deploy_aks_admin" {
  for_each = azurerm_resource_group.env

  scope                = each.value.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azurerm_user_assigned_identity.github[each.key].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Apply Kubernetes manifests via Entra-authenticated kubectl."
}

# ─── Human operators ──────────────────────────────────────────────────────
resource "azurerm_role_assignment" "operator_aks_admin" {
  for_each = {
    for pair in setproduct(keys(azurerm_resource_group.env), tolist(local.operators)) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], principal_id = pair[1] }
  }

  scope                = azurerm_resource_group.env[each.value.env].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value.principal_id
  description          = "Break-glass / operator kubectl access (Entra ID + Azure RBAC, no local accounts)."
}
