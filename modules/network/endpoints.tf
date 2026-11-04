# Private Service Connect endpoints: the company DLP reverse proxy and the control-plane services.
# The consumer side lives in this project and needs no permission in the producer's project.

resource "google_compute_address" "endpoint" {
  for_each = local.endpoints

  project      = var.project_id
  name         = "${var.name}-${each.key}"
  region       = var.region
  subnetwork   = google_compute_subnetwork.this[var.endpoint_subnet].id
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "endpoint" {
  for_each = local.endpoints

  project               = var.project_id
  name                  = "${var.name}-${each.key}"
  region                = var.region
  network               = google_compute_network.this.id
  ip_address            = google_compute_address.endpoint[each.key].id
  target                = each.value
  load_balancing_scheme = "" # empty for an endpoint to a published service
}

# DNS: Google APIs on the private VIP, and stable names for the endpoints.

resource "google_dns_managed_zone" "google_apis" {
  for_each = toset(var.google_api_domains)

  project     = var.project_id
  name        = "${var.name}-${replace(each.value, ".", "-")}"
  dns_name    = "${each.value}."
  description = "${each.value} on private.googleapis.com (no internet egress)"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

resource "google_dns_record_set" "google_apis_vip" {
  for_each = toset(var.google_api_domains)

  project      = var.project_id
  managed_zone = google_dns_managed_zone.google_apis[each.value].name
  name         = each.value == "googleapis.com" ? "private.googleapis.com." : "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = local.google_apis_ips
}

resource "google_dns_record_set" "google_apis_wildcard" {
  for_each = toset(var.google_api_domains)

  project      = var.project_id
  managed_zone = google_dns_managed_zone.google_apis[each.value].name
  name         = "*.${each.value}."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [each.value == "googleapis.com" ? "private.googleapis.com." : "${each.value}."]
}

resource "google_dns_managed_zone" "internal" {
  count = length(local.endpoints) > 0 ? 1 : 0

  project     = var.project_id
  name        = "${var.name}-internal"
  dns_name    = var.dns_domain
  description = "Private Service Connect endpoints of ${var.name}"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

resource "google_dns_record_set" "endpoint" {
  for_each = local.endpoints

  project      = var.project_id
  managed_zone = google_dns_managed_zone.internal[0].name
  name         = each.key == "dlp-proxy" ? "dlp-proxy.${var.dns_domain}" : "${trimprefix(each.key, "cp-")}.cp.${var.dns_domain}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.endpoint[each.key].address]
}
