# C6: one state backend per project, with its own key, versioning and an EU region; readable only by
# this zone's pipeline identities and break-glass.

resource "google_kms_key_ring" "iac" {
  project  = var.project_id
  name     = "platform-as-iac-repo"
  location = var.region
}

resource "google_kms_crypto_key" "state" {
  name            = "terraform-state"
  key_ring        = google_kms_key_ring.iac.id
  rotation_period = "7776000s" # 90 days
  labels          = local.labels

  lifecycle {
    prevent_destroy = true
  }
}

data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "gcs_uses_state_key" {
  crypto_key_id = google_kms_crypto_key.state.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_bucket" "state" {
  project                     = var.project_id
  name                        = local.state_bucket
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = merge(local.labels, { purpose = "terraform-state" })

  versioning {
    enabled = true
  }

  # Built from strings (not the key's id) so C6 can check at plan time that the key is this
  # project's own; depends_on orders the key first.
  encryption {
    default_kms_key_name = "projects/${var.project_id}/locations/${var.region}/keyRings/${google_kms_key_ring.iac.name}/cryptoKeys/terraform-state"
  }

  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 100
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_kms_crypto_key.state, google_kms_crypto_key_iam_member.gcs_uses_state_key]
}

# Pipeline identities: plan reads, apply reads and writes. In the control-plane bucket, which also
# holds bootstrap's state, they only reach objects under zones/control-plane/ and may list names.

locals {
  state_grants = {
    plan  = { member = "serviceAccount:${local.sa.plan}", role = "roles/storage.objectViewer" }
    apply = { member = "serviceAccount:${local.sa.apply}", role = "roles/storage.objectAdmin" }
  }
}

resource "google_storage_bucket_iam_member" "pipeline" {
  for_each = local.state_grants

  bucket = google_storage_bucket.state.name
  role   = each.value.role
  member = each.value.member

  dynamic "condition" {
    for_each = var.state_prefix_only ? [1] : []
    content {
      title      = "zones/${var.zone}/ only"
      expression = "resource.name.startsWith(\"projects/_/buckets/${local.state_bucket}/objects/${local.state_prefix}\")"
    }
  }

  depends_on = [google_service_account.pipeline]
}

resource "google_storage_bucket_iam_member" "pipeline_list" {
  for_each = var.state_prefix_only ? local.state_grants : {}

  bucket = google_storage_bucket.state.name
  role   = "roles/storage.legacyBucketReader" # list object names; reading them needs the grant above
  member = each.value.member

  depends_on = [google_service_account.pipeline]
}

resource "google_storage_bucket_iam_member" "break_glass" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = var.break_glass_group
}
