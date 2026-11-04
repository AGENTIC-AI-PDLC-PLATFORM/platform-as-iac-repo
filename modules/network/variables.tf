variable "project_id" {
  description = "Project that holds the network."
  type        = string
}

variable "name" {
  description = "Network name; also the prefix of its subnets, routes, firewall rules and endpoints."
  type        = string
}

variable "region" {
  description = "EU region of the subnets and endpoints."
  type        = string

  validation {
    condition     = startswith(var.region, "europe-")
    error_message = "The platform runs in EU regions only (europe-*)."
  }
}

variable "subnets" {
  description = "Subnets by name => primary IPv4 range. No subnet gets external IPs, NAT or a route to the internet."
  type        = map(string)
}

variable "endpoint_subnet" {
  description = "Key of var.subnets that holds the Private Service Connect endpoints (DLP proxy and control-plane services). Required when either is set."
  type        = string
  default     = null

  validation {
    condition = (
      (var.dlp_proxy == null && length(var.private_service_endpoints) == 0)
      || contains(keys(var.subnets), coalesce(var.endpoint_subnet, "-"))
    )
    error_message = "endpoint_subnet must name one of var.subnets when dlp_proxy or private_service_endpoints is set."
  }
}

variable "dlp_proxy" {
  description = "The company DLP reverse proxy, published to this project through Private Service Connect (the service attachment) and used as an explicit proxy on this port. Null: no proxy endpoint, so nothing leaves the network except calls to Google APIs."
  type = object({
    service_attachment = string
    port               = number
  })
  default = null
}

variable "private_service_endpoints" {
  description = "Control-plane services this network reaches through Private Service Connect: name => service attachment."
  type        = map(string)
  default     = {}
}

variable "dns_domain" {
  description = "Private DNS domain for the endpoints: dlp-proxy.<domain> and <service>.cp.<domain>."
  type        = string
  default     = "pdlc.internal."

  validation {
    condition     = endswith(var.dns_domain, ".")
    error_message = "dns_domain must end with a dot."
  }
}

variable "google_api_domains" {
  description = "Domains resolved to private.googleapis.com, so Google APIs are reached without internet egress."
  type        = list(string)
  default     = ["googleapis.com", "pkg.dev"]
}
