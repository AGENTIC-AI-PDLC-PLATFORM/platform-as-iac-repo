variable "project_id" {
  description = "Control-plane project (platform-team account)."
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
  description = "Control-plane subnets: name => range."
  type        = map(string)
}

variable "psc_nat_cidr" {
  description = "Range of the Private Service Connect NAT subnet behind the published services."
  type        = string
}

variable "dlp_proxy" {
  description = "Company DLP reverse proxy (Private Service Connect service attachment and port), the control plane's only egress."
  type = object({
    service_attachment = string
    port               = number
  })
}

variable "consumer_projects" {
  description = "Projects allowed to connect to the published services: the Build and Run projects (and later each regional replica, ADR-010)."
  type        = map(string)
}

variable "published_services" {
  description = "Control-plane services published to the zones: name => internal forwarding rule (agent registry, skills registry, bundle server, vault, WORM ingest, Temporal, gate; from Day 31)."
  type        = map(string)
  default     = {}
}

variable "connectivity_probe" {
  description = "Publish a small HTTP service named probe, so Build and Run can prove private connectivity to the control plane (Day 17, design review #1)."
  type        = bool
  default     = true
}
