output "project_id" {
  description = "Project of the zone."
  value       = var.project_id
}

output "state_bucket" {
  description = "State bucket of the zone."
  value       = google_storage_bucket.state.name
}

output "service_accounts" {
  description = "Runner, plan and apply identities."
  value       = local.sa
}

output "runner_pool" {
  description = "Managed instance group of the zone's runners."
  value       = google_compute_region_instance_group_manager.runner.name
}

output "app_key_secret" {
  description = "Secret Manager secret that must receive the GitHub App private key."
  value       = google_secret_manager_secret.github_app_key.id
}
