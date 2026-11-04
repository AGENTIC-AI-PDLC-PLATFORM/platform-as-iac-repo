# Connectivity probe (Day 17): one small VM answering HTTP on 8080 behind an internal load balancer,
# published as the "probe" service. From a Build or Run runner:
#   curl http://probe.cp.pdlc.internal:8080   -> "control-plane probe"
# Remove it (connectivity_probe = false) once real services are published.

resource "google_service_account" "probe" {
  count = var.connectivity_probe ? 1 : 0

  project      = var.project_id
  account_id   = "cp-connectivity-probe"
  display_name = "Control-plane connectivity probe (no roles)"
}

resource "google_compute_instance_template" "probe" {
  count = var.connectivity_probe ? 1 : 0

  project      = var.project_id
  name_prefix  = "cp-probe-"
  machine_type = "e2-micro"

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    disk_type    = "pd-balanced"
  }

  network_interface {
    subnetwork = module.network.subnet_ids["services"]
  }

  service_account {
    email  = google_service_account.probe[0].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    startup-script         = <<-EOT
      #!/bin/bash
      mkdir -p /srv/probe && echo "control-plane probe" > /srv/probe/index.html
      cd /srv/probe && exec python3 -m http.server 8080
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "probe" {
  count = var.connectivity_probe ? 1 : 0

  project            = var.project_id
  name               = "cp-probe"
  zone               = "${var.region}-a"
  base_instance_name = "cp-probe"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.probe[0].self_link
  }

  named_port {
    name = "http"
    port = 8080
  }
}

resource "google_compute_region_health_check" "probe" {
  count = var.connectivity_probe ? 1 : 0

  project = var.project_id
  name    = "cp-probe"
  region  = var.region

  tcp_health_check {
    port = 8080
  }
}

resource "google_compute_region_backend_service" "probe" {
  count = var.connectivity_probe ? 1 : 0

  project               = var.project_id
  name                  = "cp-probe"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.probe[0].id]

  backend {
    group          = google_compute_instance_group_manager.probe[0].instance_group
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "probe" {
  count = var.connectivity_probe ? 1 : 0

  project               = var.project_id
  name                  = "cp-probe"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  ports                 = ["8080"]
  network               = module.network.network_id
  subnetwork            = module.network.subnet_ids["services"]
  backend_service       = google_compute_region_backend_service.probe[0].id
}

# Health checks and Private Service Connect NAT reach the probe; nothing else does.
resource "google_compute_firewall" "probe_ingress" {
  count = var.connectivity_probe ? 1 : 0

  project                 = var.project_id
  name                    = "control-plane-allow-probe"
  network                 = module.network.network_name
  direction               = "INGRESS"
  priority                = 1000
  source_ranges           = [var.psc_nat_cidr, "35.191.0.0/16", "130.211.0.0/22"]
  target_service_accounts = [google_service_account.probe[0].email]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}
