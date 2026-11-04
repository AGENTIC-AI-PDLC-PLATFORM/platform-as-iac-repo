output "network_id" {
  description = "ID of the network."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the network."
  value       = google_compute_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs by name."
  value       = { for name, subnet in google_compute_subnetwork.this : name => subnet.id }
}

output "subnet_ranges" {
  description = "Subnet ranges by name."
  value       = var.subnets
}

output "dlp_proxy_address" {
  description = "IP address of the DLP reverse proxy endpoint, or null."
  value       = var.dlp_proxy == null ? null : google_compute_address.endpoint["dlp-proxy"].address
}

output "dlp_proxy_url" {
  description = "Explicit proxy URL for clients in this network (HTTPS_PROXY), or null."
  value       = var.dlp_proxy == null ? null : "http://${google_compute_address.endpoint["dlp-proxy"].address}:${var.dlp_proxy.port}"
}

output "service_endpoints" {
  description = "Control-plane service endpoints by name: IP address and DNS name."
  value = {
    for name in keys(var.private_service_endpoints) : name => {
      address  = google_compute_address.endpoint["cp-${name}"].address
      dns_name = "${name}.cp.${var.dns_domain}"
    }
  }
}
