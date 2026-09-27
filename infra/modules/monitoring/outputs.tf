output "log_analytics_workspace_id" {
  description = "Resource ID of the central workspace - every diagnostic setting points here."
  value       = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  description = "Name of the central workspace."
  value       = azurerm_log_analytics_workspace.this.name
}

output "log_analytics_customer_id" {
  description = "Workspace (customer) GUID used in KQL / az monitor queries."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "application_insights_id" {
  description = "Resource ID of App Insights (scope for the app's Monitoring Metrics Publisher role)."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = <<-EOT
    Tells the app WHERE to send telemetry. With local auth disabled it is not a
    credential (ingestion also needs an Entra token), but the provider marks it
    sensitive, so Terraform keeps it out of plan output.
  EOT
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
