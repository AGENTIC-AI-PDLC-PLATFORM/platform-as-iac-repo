# Run zone: Deploy & Run agents 11-15, prod account, prod credentials and data. The promote path
# (build -> human validation gate -> run, through the control plane) is the only crossing from
# Build (ADR-003): no route, peering or endpoint here leads to the Build zone, and only this zone's
# runners can obtain its credentials (C1). Every apply waits for a second approver.

module "network" {
  source = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/network?ref=network-v0.1.0"

  project_id                = var.project_id
  name                      = "run"
  region                    = var.region
  subnets                   = var.subnets
  endpoint_subnet           = "endpoints"
  dlp_proxy                 = var.dlp_proxy
  private_service_endpoints = var.control_plane_services
}

# Same module and release line as zones/build; Run follows Build, at most one release behind (C10).
module "data_plane" {
  source = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/data-plane?ref=data-plane-v0.1.0"

  zone                    = "run"
  project_id              = var.project_id
  region                  = var.region
  network_id              = module.network.network_id
  subnet_ids              = module.network.subnet_ids
  dlp_proxy_url           = module.network.dlp_proxy_url
  control_plane_endpoints = module.network.service_endpoints
}
