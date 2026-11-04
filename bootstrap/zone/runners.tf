# The zone's runner pool (ADR: plan and apply run on runners inside the zone). Each VM:
#   - sits in a runner network with no internet route; GitHub, HashiCorp and Debian are reached
#     through the company DLP reverse proxy (C5);
#   - registers one just-in-time GitHub runner in this zone's runner group, runs one job, stops;
#     the managed instance group then recreates it from the template (ephemeral, patched image);
#   - runs the job as a user that cannot reach the metadata server, so the job gets credentials
#     only from the local token broker (files/broker.py), which checks the job's GitHub OIDC token.

module "runner_network" {
  source = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/network?ref=network-v0.1.0"

  project_id      = var.project_id
  name            = "iac-runners"
  region          = var.region
  subnets         = { runners = var.runner_cidr }
  endpoint_subnet = "runners"
  dlp_proxy       = var.dlp_proxy
}

# GitHub App private key (organization permission "Self-hosted runners: read and write"). The value
# is added by hand after the apply (README), so it never enters Terraform state.
resource "google_secret_manager_secret" "github_app_key" {
  project   = var.project_id
  secret_id = "github-runner-app-key"
  labels    = local.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_iam_member" "runner_reads_app_key" {
  project    = var.project_id
  secret_id  = google_secret_manager_secret.github_app_key.secret_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${local.sa.runner}"
  depends_on = [google_service_account.pipeline]
}

locals {
  runner_config = {
    zone       = var.zone
    project_id = var.project_id
    proxy = {
      address = module.runner_network.dlp_proxy_address
      port    = var.dlp_proxy.port
    }
    github = {
      organization    = var.github.organization
      app_id          = var.github.app_id
      installation_id = var.github.installation_id
      runner_group_id = var.github.runner_group_id
      labels          = ["platform-as-iac-repo", "zone-${var.zone}"]
    }
    tools = var.runner.tools
    broker = {
      zone             = var.zone
      project_id       = var.project_id
      repository       = "${var.github.organization}/${var.github.repository}"
      audience         = "platform-as-iac-repo-broker"
      apply_workflow   = "${var.github.organization}/${var.github.repository}/.github/workflows/apply.yml"
      port             = 8099
      service_accounts = { plan = local.sa.plan, apply = local.sa.apply }
    }
  }
}

resource "google_compute_region_instance_template" "runner" {
  project      = var.project_id
  region       = var.region
  name_prefix  = "gh-runner-${var.zone}-"
  description  = "Ephemeral GitHub Actions runner of the ${var.zone} zone: one job per VM"
  machine_type = var.runner.machine_type
  labels       = merge(local.labels, { role = "github-runner" })

  disk {
    source_image = var.runner.image
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = "pd-balanced"
  }

  network_interface {
    subnetwork = module.runner_network.subnet_ids["runners"]
    # No access_config: no external IP.
  }

  service_account {
    email  = local.sa.runner
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    startup-script              = file("${path.module}/files/runner-startup.sh")
    platform-as-iac-repo-broker = file("${path.module}/files/broker.py")
    platform-as-iac-repo-config = jsonencode(local.runner_config)
    enable-oslogin              = "TRUE"
    block-project-ssh-keys      = "TRUE"
    serial-port-enable          = "FALSE"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_service_account.pipeline]
}

resource "google_compute_region_instance_group_manager" "runner" {
  project            = var.project_id
  name               = "gh-runner-${var.zone}"
  region             = var.region
  base_instance_name = "gh-runner-${var.zone}"
  target_size        = var.runner.count

  version {
    name              = "runner"
    instance_template = google_compute_region_instance_template.runner.self_link
  }

  # A new template reaches the pool as VMs are recreated after their job; running jobs are not cut.
  update_policy {
    type                  = "OPPORTUNISTIC"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }

  # A VM stops itself after its job; the group recreates it from the latest template.
  instance_lifecycle_policy {
    default_action_on_failure = "REPAIR"
    force_update_on_repair    = "YES"
  }
}
