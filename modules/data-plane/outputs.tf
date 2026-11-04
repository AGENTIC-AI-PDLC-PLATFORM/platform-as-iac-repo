output "zone" {
  description = "Zone this instance serves."
  value       = var.zone
}

output "contract" {
  description = "What the zone hands to the data plane: placement, network, egress and control-plane endpoints."
  value = {
    project_id              = var.project_id
    region                  = var.region
    network_id              = var.network_id
    subnet_ids              = var.subnet_ids
    dlp_proxy_url           = var.dlp_proxy_url
    control_plane_endpoints = var.control_plane_endpoints
  }
}
