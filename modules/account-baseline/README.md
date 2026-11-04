# modules/account-baseline

The Day 16 guardrails of one zone project. Only `bootstrap/` uses it, because setting
organisation policies needs `roles/orgpolicy.policyAdmin` at organisation level, which no zone
identity holds (C2).

| Guardrail (roadmap Day 16) | Implementation |
|---|---|
| Organisation policies | Project-level org policies: no external IPs, internal load balancers only, no VPC peering, no IP forwarding, EU locations only, no service-account keys, no workload identity federation into the project, OS Login, no serial port, public access prevention, uniform bucket access, no public Cloud SQL, internal-only Cloud Run and Cloud Functions, optional domain-restricted sharing |
| No public ingress | The constraints above, plus `modules/network` (no route to the internet) |
| Central logging | Audit-log sink to the central log bucket in the control-plane project |
| Tags for cost allocation | Project labels (set by `bootstrap/`) and provider `default_labels` in each zone root |
| C8 | Log-match alert on Admin Activity by any principal other than the zone's apply identity |

APIs are enabled only after the policies exist, so no default network and no automatic
service-account grant is ever created.
