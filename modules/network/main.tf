# Private network with egress-deny by default (ADR-001; C3 and C5):
# - the VPC is created without the default route to the internet gateway, and no NAT exists;
# - the only route that leaves the VPC is the one to private.googleapis.com (Google APIs);
# - the company DLP reverse proxy and the control-plane services are Private Service Connect
#   endpoints inside the subnets: one-way, so no zone can reach another through them.

locals {
  # private.googleapis.com, reachable without external IPs through Private Google Access
  google_apis_range = "199.36.153.8/30"
  google_apis_ips   = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]

  endpoints = merge(
    var.dlp_proxy == null ? {} : { "dlp-proxy" = var.dlp_proxy.service_attachment },
    { for name, attachment in var.private_service_endpoints : "cp-${name}" => attachment },
  )
}

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  # No route to the internet gateway is ever created for this network (C5).
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "this" {
  for_each = var.subnets

  project                  = var.project_id
  name                     = "${var.name}-${each.key}"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = each.value
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Google APIs through private.googleapis.com: the only route to the internet gateway (C5 allows it).
resource "google_compute_route" "google_apis" {
  project          = var.project_id
  name             = "${var.name}-google-apis"
  network          = google_compute_network.this.name
  dest_range       = local.google_apis_range
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}
