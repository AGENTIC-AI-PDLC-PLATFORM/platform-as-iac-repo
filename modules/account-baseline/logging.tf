# Central logging from day one, and C8: alert on any change made by a principal other than the
# zone's apply identity (break-glass included: each alert is reviewed against the break-glass record).

resource "google_logging_project_sink" "central" {
  project                = var.project_id
  name                   = "platform-audit-to-central"
  description            = "Audit logs of the ${var.zone} zone to the central bucket in the control-plane project"
  destination            = var.central_log_bucket
  filter                 = "logName:\"cloudaudit.googleapis.com\""
  unique_writer_identity = true

  depends_on = [google_project_service.this]
}

locals {
  # Admin Activity entries, minus the apply identity and Google-managed service agents
  # (service-<number>@... and <number>@cloudservices.gserviceaccount.com).
  c8_filter = join(" AND ", [
    "logName=\"projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity\"",
    "NOT protoPayload.authenticationInfo.principalEmail=\"${var.pipeline_apply_identity}\"",
    "NOT protoPayload.authenticationInfo.principalEmail=~\"^(service-[0-9]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com|[0-9]+@cloudservices\\.gserviceaccount\\.com)$\"",
  ])
}

resource "google_monitoring_notification_channel" "c8" {
  for_each = toset(var.alert_emails)

  project      = var.project_id
  display_name = "platform-as-iac-repo C8 (${var.zone}): ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }

  depends_on = [google_project_service.this]
}

resource "google_monitoring_alert_policy" "c8_change_outside_pipeline" {
  project      = var.project_id
  display_name = "platform-as-iac-repo C8: change outside the pipeline (${var.zone})"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Admin Activity by a principal other than the apply identity"

    condition_matched_log {
      filter = local.c8_filter
      label_extractors = {
        principal = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
        method    = "EXTRACT(protoPayload.methodName)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "86400s"
  }

  notification_channels = [for channel in google_monitoring_notification_channel.c8 : channel.id]

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      C8 (ADR "Zone isolation in IaC"): something in the ${var.zone} project was changed by a principal
      other than the pipeline's apply identity. If it was a recorded break-glass action, link the record;
      otherwise treat it as an incident and bring the change back under the pipeline.
    EOT
  }
}
