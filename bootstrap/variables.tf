variable "projects" {
  description = "The three zone projects (the ADR's accounts), keyed by zone."
  type = map(object({
    project_id = string
    name       = string
  }))

  validation {
    condition     = toset(keys(var.projects)) == toset(["control-plane", "build", "run"])
    error_message = "projects must have exactly the keys control-plane, build and run."
  }
}

variable "create_projects" {
  description = "true: bootstrap creates the projects in var.folder_id. false: they were created by the company's project factory (the Day 3 request) and bootstrap only configures them."
  type        = bool
  default     = true
}

variable "folder_id" {
  description = "Numeric ID of the folder that holds the three projects (when create_projects is true)."
  type        = string
  default     = null
}

variable "billing_account" {
  description = "Billing account of the three projects (when create_projects is true)."
  type        = string
  default     = null
}

variable "quota_project_id" {
  description = "Existing project billed for the bootstrap's own API calls (needs the Org Policy, Resource Manager, Service Usage and Billing APIs). Null: the ADC quota project."
  type        = string
  default     = null
}

variable "region" {
  description = "EU region for state backends, runners and logs."
  type        = string
  default     = "europe-west9"

  validation {
    condition     = startswith(var.region, "europe-")
    error_message = "State backends and runners stay in an EU region (C6)."
  }
}

variable "cost_center" {
  description = "Cost-allocation label on every project and resource."
  type        = string
}

variable "break_glass_group" {
  description = "Google group of the break-glass holders (the two named people's emergency access), as an IAM member: group:...@... ."
  type        = string

  validation {
    condition     = startswith(var.break_glass_group, "group:")
    error_message = "break_glass_group must be an IAM member of the form group:name@domain."
  }
}

variable "security_alert_emails" {
  description = "Who receives C8 alerts: the CoE security engineer."
  type        = list(string)
}

variable "allowed_policy_member_customer_ids" {
  description = "Cloud Identity customer IDs allowed in IAM policies (domain-restricted sharing). Empty: not enforced."
  type        = list(string)
  default     = []
}

variable "audit_log_retention_days" {
  description = "Retention of the central audit log bucket (Standard 9 sets the final value on Day 47)."
  type        = number
  default     = 400
}

variable "github" {
  description = "GitHub side of the runners: the organization and repository, the GitHub App that registers runners (organization permission Self-hosted runners: read and write), and one runner group per zone (from scripts/configure-github.sh)."
  type = object({
    organization     = string
    repository       = string
    app_id           = string
    installation_id  = string
    runner_group_ids = map(number)
  })

  validation {
    condition     = toset(keys(var.github.runner_group_ids)) == toset(["control-plane", "build", "run"])
    error_message = "github.runner_group_ids needs one runner group per zone: control-plane, build, run."
  }
}

variable "dlp_proxy" {
  description = "The company DLP reverse proxy as a Private Service Connect service attachment, and its proxy port. Every runner reaches GitHub, HashiCorp and Debian through it."
  type = object({
    service_attachment = string
    port               = number
  })
}

variable "runner_cidrs" {
  description = "Subnet range of each zone's runner network."
  type        = map(string)
  default = {
    control-plane = "10.10.0.0/24"
    build         = "10.20.0.0/24"
    run           = "10.30.0.0/24"
  }
}

variable "runner" {
  description = "Runner pool settings, the same in each zone. Tool versions are pinned; checksums are verified at boot."
  type = object({
    count        = optional(number, 2)
    machine_type = optional(string, "e2-standard-2")
    image        = optional(string, "debian-cloud/debian-12")
    tools = optional(object({
      terraform_version = string
      terraform_sha256  = string # empty: taken from HashiCorp's SHA256SUMS at boot
      opa_version       = string
      opa_sha256        = string
      runner_version    = string
      runner_sha256     = string
      }), {
      terraform_version = "1.17.1"
      terraform_sha256  = ""
      opa_version       = "1.22.0"
      opa_sha256        = "791790254c598a942eb140959bcec9a47f844535a632fd01d11d870ba2a47047"
      runner_version    = "2.338.2"
      runner_sha256     = "baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"
    })
  })
  default = {}
}

variable "plan_roles" {
  description = "Project roles of each zone's plan identity: read everything Terraform refreshes, plus IAM policies and Cloud Asset (C2 scan)."
  type        = list(string)
  default = [
    "roles/viewer",
    "roles/iam.securityReviewer",
    "roles/cloudasset.viewer",
  ]
}

variable "apply_roles" {
  description = "Project roles of each zone's apply identity, in its own project only (C2)."
  type        = list(string)
  default = [
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    "roles/cloudkms.admin",
    "roles/secretmanager.admin",
    "roles/networkmanagement.admin",
  ]
}
