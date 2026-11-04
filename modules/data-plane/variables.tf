variable "zone" {
  description = "build or run: the one module serves both zones (ADR-002)."
  type        = string

  validation {
    condition     = contains(["build", "run"], var.zone)
    error_message = "zone must be build or run."
  }
}

variable "project_id" {
  description = "Project of the zone."
  type        = string
}

variable "region" {
  description = "EU region of the zone."
  type        = string
}

variable "network_id" {
  description = "Zone network, from modules/network."
  type        = string
}

variable "subnet_ids" {
  description = "Zone subnets by name, from modules/network."
  type        = map(string)
}

variable "dlp_proxy_url" {
  description = "Explicit proxy URL of the company DLP reverse proxy endpoint: the only egress (C5)."
  type        = string
}

variable "control_plane_endpoints" {
  description = "Control-plane services reachable from the zone, by name: address and DNS name."
  type = map(object({
    address  = string
    dns_name = string
  }))
  default = {}
}
