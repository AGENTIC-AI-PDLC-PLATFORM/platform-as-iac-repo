# Shared control-plane zone, instantiated once (ADR-002). Both zones are private-network clients:
# each control-plane service is published through Private Service Connect to the Build and Run
# projects only. The connection is one-way, so the control plane never opens a path into a zone,
# and Build and Run never get a path to each other (ADR-003).

module "network" {
  source = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/network?ref=network-v0.1.0"

  project_id      = var.project_id
  name            = "control-plane"
  region          = var.region
  subnets         = var.subnets
  endpoint_subnet = "services"
  dlp_proxy       = var.dlp_proxy
}

resource "google_compute_subnetwork" "psc_nat" {
  project       = var.project_id
  name          = "control-plane-psc-nat"
  region        = var.region
  network       = module.network.network_id
  ip_cidr_range = var.psc_nat_cidr
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

locals {
  services = merge(
    var.published_services,
    var.connectivity_probe ? { probe = google_compute_forwarding_rule.probe[0].self_link } : {},
  )
}

resource "google_compute_service_attachment" "this" {
  for_each = local.services

  project               = var.project_id
  name                  = each.key
  region                = var.region
  description           = "Control-plane service ${each.key}, for the Build and Run zones only"
  target_service        = each.value
  nat_subnets           = [google_compute_subnetwork.psc_nat.id]
  enable_proxy_protocol = false
  connection_preference = "ACCEPT_MANUAL"

  dynamic "consumer_accept_lists" {
    for_each = var.consumer_projects
    content {
      project_id_or_num = consumer_accept_lists.value
      connection_limit  = 10
    }
  }
}
