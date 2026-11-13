# Build zone: Design & Build agents 1-9, non-prod account, synthetic or masked data only.
# The network has no route out except Google APIs; egress goes through the company DLP reverse proxy
# and the control plane is reached through its published services (C3, C5). No route, peering or
# endpoint leads to the Run zone (ADR-003).

module "network" {
  source = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/network?ref=network-v0.1.0"

  project_id                = var.project_id
  name                      = "build"
  region                    = var.region
  subnets                   = var.subnets
  endpoint_subnet           = "endpoints"
  dlp_proxy                 = var.dlp_proxy
  private_service_endpoints = var.control_plane_services
}

# Same module and release line as zones/run; Build moves first (C10).
module "data_plane" {
  source = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/data-plane?ref=data-plane-v0.1.0"

  zone                    = "build"
  project_id              = var.project_id
  region                  = var.region
  network_id              = module.network.network_id
  subnet_ids              = module.network.subnet_ids
  dlp_proxy_url           = module.network.dlp_proxy_url
  control_plane_endpoints = module.network.service_endpoints
}
