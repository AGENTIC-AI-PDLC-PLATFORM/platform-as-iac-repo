# One zone's stage-0 resources, all inside its own project:
#   state.tf     state bucket and its key (C6)
#   identity.tf  runner, plan and apply service accounts (C1, C2, C7)
#   runners.tf   runner network and pool: ephemeral GitHub runners with a local token broker (C1)
#
# Service-account emails and resource names are built from strings rather than read from the
# resources, so the bootstrap plan already shows the values C1 and C6 check.

locals {
  sa = {
    runner = "platform-as-iac-repo-runner@${var.project_id}.iam.gserviceaccount.com"
    plan   = "platform-as-iac-repo-plan@${var.project_id}.iam.gserviceaccount.com"
    apply  = "platform-as-iac-repo-apply@${var.project_id}.iam.gserviceaccount.com"
  }
  sa_id = { for role, email in local.sa : role => "projects/${var.project_id}/serviceAccounts/${email}" }

  state_bucket = "${var.project_id}-tfstate"
  state_prefix = "zones/${var.zone}/"

  # managed-by and cost-center come from the provider's default_labels.
  labels = {
    zone = var.zone
  }
}
