# Guardrails of one zone project, set as organisation policies on the project (Day 16): no public
# ingress, no static keys, no federation, EU only, no peering. Setting them needs the Organization
# Policy Administrator role, so only bootstrap/ instantiates this module.

locals {
  boolean_constraints = [
    "compute.skipDefaultNetworkCreation",
    "compute.requireOsLogin",
    "compute.disableSerialPortAccess",
    "iam.disableServiceAccountKeyCreation", # C7: no static cloud credentials
    "iam.disableServiceAccountKeyUpload",   # C7
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "storage.publicAccessPrevention",
    "storage.uniformBucketLevelAccess",
    "sql.restrictPublicIp",
  ]

  # deny_all = true, or the list of allowed values
  list_constraints = merge(
    {
      "compute.vmExternalIpAccess"                         = { deny_all = true, allowed = [] } # no public ingress
      "compute.restrictVpcPeering"                         = { deny_all = true, allowed = [] } # C3: no peering at all
      "compute.vmCanIpForward"                             = { deny_all = true, allowed = [] } # no routing appliances
      "iam.workloadIdentityPoolProviders"                  = { deny_all = true, allowed = [] } # no federation into the zone
      "iam.workloadIdentityPoolAwsAccounts"                = { deny_all = true, allowed = [] }
      "compute.restrictLoadBalancerCreationForTypes"       = { deny_all = false, allowed = ["in:INTERNAL"] }
      "compute.restrictProtocolForwardingCreationForTypes" = { deny_all = false, allowed = ["INTERNAL"] }
      "gcp.resourceLocations"                              = { deny_all = false, allowed = ["in:eu-locations"] }
      "run.allowedIngress"                                 = { deny_all = false, allowed = ["internal"] }
      "cloudfunctions.allowedIngressSettings"              = { deny_all = false, allowed = ["ALLOW_INTERNAL_ONLY"] }
    },
    length(var.allowed_policy_member_customer_ids) == 0 ? {} : {
      "iam.allowedPolicyMemberDomains" = { deny_all = false, allowed = var.allowed_policy_member_customer_ids }
    },
  )
}

resource "google_org_policy_policy" "boolean" {
  for_each = toset(local.boolean_constraints)

  name   = "projects/${var.project_id}/policies/${each.value}"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "list" {
  for_each = local.list_constraints

  name   = "projects/${var.project_id}/policies/${each.key}"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      deny_all = each.value.deny_all ? "TRUE" : null

      dynamic "values" {
        for_each = each.value.deny_all ? [] : [each.value.allowed]
        content {
          allowed_values = values.value
        }
      }
    }
  }
}

resource "google_project_service" "this" {
  for_each = toset(var.services)

  project = var.project_id
  service = each.value

  depends_on = [google_org_policy_policy.boolean, google_org_policy_policy.list]
}
