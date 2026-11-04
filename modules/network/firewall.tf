# Egress-deny default: a VM may only reach Google APIs and addresses inside this network (where the
# Private Service Connect endpoints live). Ingress from outside the network is denied by GCP's
# implied rule; nothing here opens it.

resource "google_compute_firewall" "deny_all_egress" {
  project            = var.project_id
  name               = "${var.name}-deny-all-egress"
  network            = google_compute_network.this.name
  direction          = "EGRESS"
  priority           = 65000
  destination_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_egress_google_apis" {
  project            = var.project_id
  name               = "${var.name}-allow-egress-google-apis"
  network            = google_compute_network.this.name
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = [local.google_apis_range]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "allow_egress_internal" {
  project            = var.project_id
  name               = "${var.name}-allow-egress-internal"
  network            = google_compute_network.this.name
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = values(var.subnets)

  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "allow_ingress_internal" {
  project       = var.project_id
  name          = "${var.name}-allow-ingress-internal"
  network       = google_compute_network.this.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = values(var.subnets)

  allow {
    protocol = "all"
  }
}
