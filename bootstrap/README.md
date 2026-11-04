# bootstrap/ — stage 0

Applied **once, on Day 16, by two named people, from the control-plane project**; then its
credentials are locked as break-glass (ADR "Zone isolation in IaC"). No pipeline can plan or apply
it: it creates the very identities and runners the pipelines use. The CISO delegate keeps the
break-glass record and checks it at the risk and security review.

It creates, in each of the three projects (control plane, Build, Run):

| What | File | Control |
|---|---|---|
| The project (or adopts it), a deletion lien, project labels | `main.tf` | |
| Organisation policies, then the APIs, the audit-log sink and the C8 alert | `modules/account-baseline` | C7, C8 |
| The central audit-log bucket (control-plane project) | `main.tf` | |
| State bucket with its own KMS key, versioning, EU region, readable only by the zone | `zone/state.tf` | C6 |
| `platform-as-iac-repo-runner`, `-plan`, `-apply` service accounts, no keys | `zone/identity.tf` | C1, C2, C7 |
| Runner network (egress through the DLP reverse proxy only), runner pool, GitHub App key secret | `zone/runners.tf` | C1, C3, C5 |

## Who and what is needed

- Two named people, members of a temporary admin group holding: Project Creator on the folder,
  Billing Account User, Organization Policy Administrator on the organization. (With
  `create_projects = false`, Owner on the three existing projects instead of the first two.)
- An existing quota project with the Cloud Resource Manager, Service Usage, Cloud Billing, IAM and
  Organization Policy APIs enabled (`quota_project_id`).
- The release tags `account-baseline-v0.1.0` and `network-v0.1.0`, and git access to this repository.
- The GitHub App (app ID, installation ID, private key) and the runner group IDs printed by
  `scripts/configure-github.sh`.
- Terraform 1.17.1 (`.terraform-version`) and OPA, for the evidence step.

## Procedure

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars        # fill in; never committed
gcloud auth application-default login
terraform init                                      # local state for now
terraform plan -out=bootstrap.tfplan                # both people review it
terraform apply bootstrap.tfplan
```

Give each zone's runners the GitHub App key (they wait for it, then register):

```bash
for project in <control-plane-project> <build-project> <run-project>; do
  gcloud secrets versions add github-runner-app-key --project="$project" --data-file=app-key.pem
done
shred -u app-key.pem
```

Move bootstrap's state into the control-plane bucket (prefix `bootstrap/`, readable only by
break-glass), and commit `backend.tf` through a pull request:

```bash
cp backend.tf.example backend.tf                    # bucket from: terraform output bootstrap_backend_hcl
terraform init -migrate-state
rm terraform.tfstate terraform.tfstate.backup
```

Record the evidence for C1 and C6 (values unknown before the first apply are known now):

```bash
terraform plan -out=check.tfplan && terraform show -json check.tfplan > check.json
../scripts/check-plan.sh bootstrap check.json       # C1 C3 C4 C5 C6 C9: attach the output to the break-glass record
```

Check each `zones/<zone>/backend.hcl` against `terraform output zones`, then confirm the runners
are online (organization settings → Actions → Runners, groups `platform-as-iac-repo-<zone>`).

**Lock it:** remove both people from the temporary admin group. `break_glass_group` stays empty
except during a recorded break-glass; every action taken then raises a C8 alert.

## Later changes

A change here is a break-glass operation: pull request reviewed by the code owners (Squad B lead,
CoE security engineer), then applied by two named people with the procedure above and a new
break-glass record. The pull-request pipeline runs the C1 negative test from a Build runner on every
change to `bootstrap/`.
