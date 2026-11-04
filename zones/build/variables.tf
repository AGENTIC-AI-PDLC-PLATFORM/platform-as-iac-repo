variable "project_id" {
  description = "Build-zone project (non-prod account: synthetic or masked data only, ADR-006)."
  type        = string
}

variable "region" {
  description = "EU region."
  type        = string
  default     = "europe-west9"
}

variable "cost_center" {
  description = "Cost-allocation label."
  type        = string
}

variable "subnets" {
  description = "Build subnets: name => range. Must include \"endpoints\" (Private Service Connect endpoints)."
  type        = map(string)
}

variable "dlp_proxy" {
  description = "Company DLP reverse proxy (Private Service Connect service attachment and port): the zone's only egress (C5)."
  type = object({
    service_attachment = string
    port               = number
  })
}

# Read from published/control-plane.tfvars.json (-var-file): no default, so a plan without the
# published file fails instead of removing the endpoints.
variable "control_plane_services" {
  description = "Control-plane services published to the zones: name => service attachment."
  type        = map(string)
}
