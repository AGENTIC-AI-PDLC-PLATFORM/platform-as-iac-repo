output "log_sink_writer_identity" {
  description = "Identity that writes this project's audit logs to the central bucket; needs roles/logging.bucketWriter there."
  value       = google_logging_project_sink.central.writer_identity
}

output "services" {
  description = "Enabled APIs, so dependants can wait for them."
  value       = [for service in google_project_service.this : service.service]
}
