variable "project_id" {
  description = "Project the guardrails apply to."
  type        = string
}

variable "zone" {
  description = "Zone of the project: control-plane, build or run."
  type        = string

  validation {
    condition     = contains(["control-plane", "build", "run"], var.zone)
    error_message = "zone must be control-plane, build or run."
  }
}

variable "services" {
  description = "APIs to enable once the organisation policies are in place (so, for example, no default network or default service-account grant is ever created)."
  type        = list(string)
}

variable "central_log_bucket" {
  description = "Central audit log bucket, as a sink destination: logging.googleapis.com/projects/<p>/locations/<l>/buckets/<b>."
  type        = string
}

variable "pipeline_apply_identity" {
  description = "Email of the zone's apply service account: the only principal expected to change the project (C8)."
  type        = string
}

variable "alert_emails" {
  description = "Who receives C8 alerts (the CoE security engineer)."
  type        = list(string)
}

variable "allowed_policy_member_customer_ids" {
  description = "Google Workspace / Cloud Identity customer IDs allowed in IAM policies (domain-restricted sharing). Empty: the constraint is not set."
  type        = list(string)
  default     = []
}
