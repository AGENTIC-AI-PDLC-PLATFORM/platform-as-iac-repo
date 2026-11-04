# C1, C2, C7. Three service accounts per zone, no keys:
#   runner  attached to this zone's runner VMs only; registers runners and mints plan/apply tokens
#           through the token broker. Jobs cannot use it: the metadata server is blocked for them.
#   plan    read-only in this project; tokens go to any job of the repository on this zone's runners.
#   apply   writes this project; tokens go only to the apply workflow on main, in this zone's
#           protected GitHub environment (Run: second approver), on this zone's runners.
# Nothing grants these identities any role outside this project, and only the runner account of
# this same project may mint plan or apply tokens: a Build runner cannot obtain a Run credential.

resource "google_service_account" "pipeline" {
  for_each = local.sa

  project      = var.project_id
  account_id   = "platform-as-iac-repo-${each.key}"
  display_name = "platform-as-iac-repo ${each.key} (${var.zone})"
  description = {
    runner = "Attached to the ${var.zone} runner VMs: registers the runner, mints plan/apply tokens for jobs that pass the broker's checks"
    plan   = "Terraform plan in the ${var.zone} project (read-only)"
    apply  = "Terraform apply in the ${var.zone} project, from the apply workflow on main only"
  }[each.key]
}

resource "google_project_iam_member" "plan" {
  for_each = toset(var.plan_roles)

  project    = var.project_id
  role       = each.value
  member     = "serviceAccount:${local.sa.plan}"
  depends_on = [google_service_account.pipeline]
}

resource "google_project_iam_member" "apply" {
  for_each = toset(var.apply_roles)

  project    = var.project_id
  role       = each.value
  member     = "serviceAccount:${local.sa.apply}"
  depends_on = [google_service_account.pipeline]
}

# The runner account mints one-hour tokens for plan and apply, and nothing else may (C1).
resource "google_service_account_iam_member" "runner_mints" {
  for_each = toset(["plan", "apply"])

  service_account_id = local.sa_id[each.key]
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.sa.runner}"
  depends_on         = [google_service_account.pipeline]
}

# The broker writes every token decision to Cloud Logging (attributable applies).
resource "google_project_iam_member" "runner_logs" {
  project    = var.project_id
  role       = "roles/logging.logWriter"
  member     = "serviceAccount:${local.sa.runner}"
  depends_on = [google_service_account.pipeline]
}

resource "google_project_iam_member" "break_glass" {
  project = var.project_id
  role    = "roles/owner"
  member  = var.break_glass_group
}
