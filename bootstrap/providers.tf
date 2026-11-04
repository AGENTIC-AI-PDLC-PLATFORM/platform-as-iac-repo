# Applied from a workstation by the two named people, with their own Application Default
# Credentials (gcloud auth application-default login). No pipeline identity exists yet.
provider "google" {
  region                = var.region
  billing_project       = var.quota_project_id
  user_project_override = var.quota_project_id != null

  default_labels = {
    managed-by  = "platform-as-iac-repo-bootstrap"
    cost-center = var.cost_center
  }
}
