terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
  }

  # This zone's own bucket, created by bootstrap/ (C6). Values in backend.hcl.
  backend "gcs" {}
}
