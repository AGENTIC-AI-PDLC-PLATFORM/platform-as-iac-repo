output "dlp_proxy_url" {
  description = "Explicit proxy for anything in the zone that needs egress (LLM gateway, MCP fleet)."
  value       = module.network.dlp_proxy_url
}

output "control_plane_endpoints" {
  description = "Control-plane services reachable from the zone."
  value       = module.network.service_endpoints
}

output "data_plane" {
  description = "What the zone hands to its data plane."
  value       = module.data_plane.contract
}
