variable "zone" {
  description = "control-plane, build or run."
  type        = string
}

variable "project_id" {
  description = "Project of the zone."
  type        = string
}

variable "region" {
  description = "EU region."
  type        = string
}

variable "break_glass_group" {
  description = "IAM member of the break-glass group."
  type        = string
}

variable "plan_roles" {
  description = "Project roles of the plan identity."
  type        = list(string)
}

variable "apply_roles" {
  description = "Project roles of the apply identity."
  type        = list(string)
}

variable "state_prefix_only" {
  description = "Limit the pipeline identities to objects under zones/<zone>/ (the bucket also holds bootstrap state)."
  type        = bool
  default     = false
}

variable "github" {
  description = "Organization, repository, GitHub App and runner group of this zone's runners."
  type = object({
    organization    = string
    repository      = string
    app_id          = string
    installation_id = string
    runner_group_id = number
  })
}

variable "dlp_proxy" {
  description = "Company DLP reverse proxy: Private Service Connect service attachment and proxy port."
  type = object({
    service_attachment = string
    port               = number
  })
}

variable "runner_cidr" {
  description = "Range of the runner subnet."
  type        = string
}

variable "runner" {
  description = "Runner pool settings."
  type = object({
    count        = number
    machine_type = string
    image        = string
    tools = object({
      terraform_version = string
      terraform_sha256  = string
      opa_version       = string
      opa_sha256        = string
      runner_version    = string
      runner_sha256     = string
    })
  })
}
