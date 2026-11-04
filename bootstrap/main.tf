# Stage 0 (ADR "Zone isolation in IaC"): applied once on Day 16 by two named people from the
# control-plane project, then locked as break-glass. Creates, per zone project: the guardrails,
# the state backend, the plan/apply/runner identities and the runner pool. Nothing here gives a
# zone's identity any permission outside its own project (C2), and no path joins Build and Run.

locals {
  # Referencing the project resource (or data source) orders everything after project creation.
  project_ids = {
    for zone, project in var.projects : zone => (
      var.create_projects ? google_project.this[zone].project_id : data.google_project.existing[zone].project_id
    )
  }
  project_numbers = {
    for zone, project in var.projects : zone => (
      var.create_projects ? google_project.this[zone].number : data.google_project.existing[zone].number
    )
  }

  services = [
    "cloudasset.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkmanagement.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ]

  audit_bucket_id = "platform-audit"
}

# Projects ----------------------------------------------------------------------------------------

resource "google_project" "this" {
  for_each = var.create_projects ? var.projects : {}

  project_id          = each.value.project_id
  name                = each.value.name
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"

  labels = {
    zone        = each.key
    cost-center = var.cost_center
    managed-by  = "platform-as-iac-repo-bootstrap"
  }
}

data "google_project" "existing" {
  for_each = var.create_projects ? {} : var.projects

  project_id = each.value.project_id
}

resource "google_resource_manager_lien" "no_delete" {
  for_each = var.projects

  parent       = "projects/${local.project_numbers[each.key]}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "platform-as-iac-repo-bootstrap"
  reason       = "Zone project of the Agentic PDLC platform (${each.key}); deleting it is a decision for the Design Authority."
}

# Central audit log bucket, in the control-plane project ("central logging on from day one") ------

resource "google_project_service" "control_plane_logging" {
  project = local.project_ids["control-plane"]
  service = "logging.googleapis.com"
}

resource "google_logging_project_bucket_config" "audit" {
  project        = local.project_ids["control-plane"]
  location       = var.region
  bucket_id      = local.audit_bucket_id
  retention_days = var.audit_log_retention_days
  description    = "Audit logs of the three platform projects (control plane, Build, Run)"

  depends_on = [google_project_service.control_plane_logging]
}

# Guardrails, then APIs, in each project -----------------------------------------------------------

module "baseline" {
  source   = "git::https://github.com/platform-team/platform-as-iac-repo.git//modules/account-baseline?ref=account-baseline-v0.1.0"
  for_each = var.projects

  project_id                         = local.project_ids[each.key]
  zone                               = each.key
  services                           = local.services
  central_log_bucket                 = "logging.googleapis.com/${google_logging_project_bucket_config.audit.id}"
  pipeline_apply_identity            = "platform-as-iac-repo-apply@${local.project_ids[each.key]}.iam.gserviceaccount.com"
  alert_emails                       = var.security_alert_emails
  allowed_policy_member_customer_ids = var.allowed_policy_member_customer_ids
}

resource "google_project_iam_member" "audit_writer" {
  for_each = var.projects

  project = local.project_ids["control-plane"]
  role    = "roles/logging.bucketWriter"
  member  = module.baseline[each.key].log_sink_writer_identity

  condition {
    title      = "platform-audit bucket only"
    expression = "resource.name.endsWith(\"locations/${var.region}/buckets/${local.audit_bucket_id}\")"
  }
}

# State backend, identities and runner pool of each zone --------------------------------------------

module "zone" {
  source   = "./zone"
  for_each = var.projects

  zone              = each.key
  project_id        = local.project_ids[each.key]
  region            = var.region
  break_glass_group = var.break_glass_group
  plan_roles        = var.plan_roles
  apply_roles       = var.apply_roles

  # The control-plane bucket also keeps bootstrap's own state (prefix bootstrap/), which only
  # break-glass may read: its pipeline identities are limited to zones/control-plane/.
  state_prefix_only = each.key == "control-plane"

  github = {
    organization    = var.github.organization
    repository      = var.github.repository
    app_id          = var.github.app_id
    installation_id = var.github.installation_id
    runner_group_id = var.github.runner_group_ids[each.key]
  }
  dlp_proxy   = var.dlp_proxy
  runner_cidr = var.runner_cidrs[each.key]
  runner      = var.runner

  depends_on = [module.baseline]
}
