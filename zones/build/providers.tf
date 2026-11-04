# Credentials come from this zone's token broker (scripts/gcp-token.sh), as GOOGLE_OAUTH_ACCESS_TOKEN.
provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed-by  = "platform-as-iac-repo"
    zone        = "build"
    cost-center = var.cost_center
  }
}
