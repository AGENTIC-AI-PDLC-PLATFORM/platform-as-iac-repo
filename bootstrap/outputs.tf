output "zones" {
  description = "Per zone: project, state backend (paste backend_hcl into zones/<zone>/backend.hcl), identities and runner pool."
  value = {
    for zone, m in module.zone : zone => {
      project_id       = m.project_id
      project_number   = local.project_numbers[zone]
      state_bucket     = m.state_bucket
      backend_hcl      = "bucket = \"${m.state_bucket}\"\nprefix = \"zones/${zone}\"\n"
      service_accounts = m.service_accounts
      runner_pool      = m.runner_pool
      app_key_secret   = m.app_key_secret
    }
  }
}

output "audit_log_bucket" {
  description = "Central audit log bucket in the control-plane project."
  value       = google_logging_project_bucket_config.audit.id
}

output "bootstrap_backend_hcl" {
  description = "Backend of bootstrap itself after the first apply (backend.tf.example)."
  value       = "bucket = \"${module.zone["control-plane"].state_bucket}\"\nprefix = \"bootstrap\"\n"
}
