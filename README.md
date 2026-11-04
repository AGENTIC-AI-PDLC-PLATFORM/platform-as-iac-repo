# platform-as-iac-repo

Infrastructure as code of the Agentic PDLC PaaS on Google Cloud, laid out as decided in the ADR
**"Zone isolation in IaC: one repository with one root, state backend and pipeline identity per
zone"** (design-authority repository). Every zone has its own root, state backend, identity and
runner pool, so this repository can never become a second Build → Run crossing (ADR-001 to ADR-003).

```text
platform-as-iac-repo/
├── bootstrap/               # stage 0, applied once on Day 16 by two named people: projects, guardrails,
│   └── zone/                #   state backends, identities, runner pools (+ token broker)
├── zones/
│   ├── control-plane/       # root: platform-team project, instantiated once
│   ├── build/               # root: non-prod project; uses modules/data-plane
│   └── run/                 # root: prod project; uses modules/data-plane
├── modules/
│   ├── account-baseline/    # guardrails: organisation policies, no public ingress, central logging, C8 alert
│   ├── network/             # private network, egress-deny default, endpoint to the DLP reverse proxy
│   └── data-plane/          # one module for both zones; filled from Day 31
├── published/               # control-plane outputs Build and Run need (non-secret, reviewed)
├── policy/                  # one plan check per control, each with a fixture plan that must fail
├── scripts/                 # what the pipelines run; GitHub setup; provider locking
├── CODEOWNERS               # zones/run/ and bootstrap/: Squad B lead + CoE security engineer; zones/control-plane/: Squad A lead
└── .github/workflows/       # plan on pull request, apply on merge, per zone; scheduled checks
```

## How the ADR maps to Google Cloud

| ADR | Here |
|---|---|
| Three accounts | Three projects: control plane, Build (non-prod), Run (prod) |
| Organisation policies, no public ingress, central logging, tags | `modules/account-baseline` (project-level org policies, audit-log sink to a central bucket), labels on every resource |
| One state backend per account, own key, versioning, EU | A GCS bucket and a Cloud KMS key in each project, `europe-west9`, readable only by that zone |
| Pipeline identity per zone, short-lived, no static keys | `platform-as-iac-repo-plan` and `platform-as-iac-repo-apply` service accounts per project, no keys; one-hour tokens |
| OIDC trust; Run roles trust only Run runners (C1) | Each zone's runner VM runs a token broker that checks the job's GitHub OIDC token and mints that zone's plan or apply token with the VM's own identity, which jobs cannot reach. Only the runner account of the same project may mint them, so a Build runner can never hold a Run credential |
| Runners inside each zone | One pool of ephemeral GitHub runners per project: one job per VM, recreated from the template after each job |
| Route to the company DLP reverse proxy, egress-deny | The proxy is a Private Service Connect endpoint used as an explicit proxy; networks have no default route, no NAT, no external IP |
| Private connectivity zones ↔ control plane | The control plane publishes services through Private Service Connect to the Build and Run projects only; one-way, so no path between zones |
| Protected environment, second approver | GitHub environment `run`: deployments from `main`, a reviewer other than the person who started the run |
| Control-plane outputs as non-secret parameters | `published/control-plane.tfvars.json`, passed to Build and Run with `-var-file` |

## Controls

| Control | Where | When |
|---|---|---|
| C1 Run identities trust only Run runners | `bootstrap/zone/identity.tf`, `files/broker.py`; `policy/c1_run_trust.rego`; `scripts/c1-negative-test.sh` | Plan check on every pull request and apply; negative test from a Build runner on every pull request touching `bootstrap/` and on demand (Day 22) |
| C2 No zone identity holds permissions outside its project | `scripts/c2-iam-scan.sh` | Weekly (Mondays), issue `IAM: <zone>` |
| C3 No Build ↔ Run peering, transit or route | `policy/c3_no_build_run_path.rego`; `scripts/reachability.sh` | Plan check on every pull request; connectivity tests after each apply |
| C4 No zone reads another zone's state | `policy/c4_no_cross_zone_state.rego` | Plan check on every pull request |
| C5 Egress only through the DLP reverse proxy | `policy/c5_egress_via_proxy.rego`; `scripts/reachability.sh` | Plan check on every pull request; connectivity tests after each apply |
| C6 One state backend per project, own key, versioning, EU, no other reader | `bootstrap/zone/state.tf`; `policy/c6_state_isolation.rego` | Bootstrap plan, by the two named people (no pipeline can plan bootstrap) |
| C7 No static credentials, tokens ≤ 1 h | Org policies (no keys), the broker (1 h tokens); `scripts/check-no-static-credentials.sh`, gitleaks | Every pull request |
| C8 No change outside the pipeline | `modules/account-baseline/logging.tf`: log-match alert on Admin Activity by anyone but the apply identity | Continuous; each alert reviewed by the CoE security engineer |
| C9 Providers locked, modules pinned | `.terraform.lock.hcl` (`init -lockfile=readonly`); `policy/c9_pinned_sources.rego` | Every pull request |
| C10 Run at most one data-plane release behind Build | `policy/c10_data_plane_parity.rego`; `scripts/check-c10.sh` | Every pull request |
| C11 Every check fails on a violating fixture | `policy/*_test.rego`, `policy/fixtures/`; `scripts/check-fixtures.sh` | Every pull request (`opa test`) |
| C12 No drift unresolved after 2 working days | `scripts/drift.sh` | Daily (weekdays), issue `Drift: <zone>` |

## First-time setup

1. **Repository.** Create `platform-as-iac-repo` in the organization, replace the placeholders, push:
   `platform-team` (organization slug, in module sources and CODEOWNERS), `example-pdlc-*` (project
   IDs, in `bootstrap/terraform.tfvars`, `zones/*/terraform.tfvars`, `zones/*/backend.hcl`,
   `published/`), the DLP reverse proxy's service attachment and port, and the IP ranges.
2. **Teams.** Run `create-teams.sh` (from the design-authority work): it gives the code-owner teams
   their own write grant on `platform-as-iac-repo`, and changes nothing while a repository it
   manages does not exist yet.
3. **Provider locks.** `scripts/lock-providers.sh`, then commit the four `.terraform.lock.hcl` (C9).
4. **Module releases.** Tag the first versions; zones and bootstrap use them:
   `git tag account-baseline-v0.1.0 && git tag network-v0.1.0 && git tag data-plane-v0.1.0 && git push --tags`
5. **GitHub App** for runner registration: organization permission *Self-hosted runners: read and
   write*, nothing else; install it on the organization; generate a private key.
6. **GitHub settings.** `ORG=<org> bash scripts/configure-github.sh`: runner groups (note their IDs),
   environments, rulesets on `main` and on release tags.
7. **Bootstrap**, Day 16, by the two named people: [bootstrap/README.md](bootstrap/README.md).
8. **First pull request** touching `zones/`: each zone is planned on its own runners; merge applies
   control plane, then Build, then Run (after the second approval).

## Working on it

- **A zone:** pull request → plan comment per zone → code-owner review → merge → ordered apply.
- **A shared module:** change `modules/<name>` (no zone is affected), merge, tag
  `<name>-vX.Y.Z`, then bump `?ref=` in `zones/build` in one pull request and in `zones/run` in
  another (C10 keeps Run at most one data-plane release behind Build).
- **A control-plane service:** add it to `published_services` in `zones/control-plane` and to
  `published/control-plane.tfvars.json` in the same pull request; the apply checks they match.
- **Break-glass:** only through the procedure in `bootstrap/README.md`; every action raises a C8
  alert that is matched against the break-glass record.

## Known limits

- `modules/data-plane` creates nothing until Day 31; its inputs fix the contract the zones honour.
- Each runner VM installs its tools at boot (1–2 minutes per job); bake an image when it matters.
- Terraform's checksum on the runners comes from HashiCorp's `SHA256SUMS` at boot until
  `runner.tools.terraform_sha256` is pinned in `bootstrap/terraform.tfvars`.
- A pull request runs its own version of the workflows on the zone runners and gets that zone's
  read-only plan credentials: the ADR accepts that planning Run needs read access in Run. Apply
  credentials go only to the apply workflow from `main`.
- On lines with two owner teams, GitHub accepts one approval from either; for Run, the
  environment approval adds the second person.
- Sovereign-region replicas (ADR-010) will each get their own root, state backend and runners.
