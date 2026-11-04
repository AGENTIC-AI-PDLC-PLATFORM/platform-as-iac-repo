terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
  }

  # State: local on the first apply, then moved to the control-plane state bucket under
  # bootstrap/ (see backend.tf.example and README.md).
}
