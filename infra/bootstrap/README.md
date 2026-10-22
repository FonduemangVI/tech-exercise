# Bootstrap

Run once, from a laptop, before any pipeline can work. It creates:

| Resource | Purpose |
|---|---|
| `wiz-ex-<region>-bootstrap-rg` | Kept separate from the main resource group, so destroying the environment never deletes state or pipeline identities |
| Storage account + `tfstate` container | Remote state for `infra/`. Shared keys disabled (Entra ID only), versioning and soft delete on, no public access |
| `id-gh-infra` | Applies `infra/` from `main` via the `prod-infra` environment (approval required) |
| `id-gh-app` | Pushes images and deploys tasky from `main` via the `prod-app` environment |
| `id-gh-pr` | Read-only identity for plan and build jobs on pull requests |

Each identity has one federated credential that trusts a single GitHub OIDC subject. No client secrets exist.

The repo uses GitHub's immutable OIDC subjects, which name the owner and repo by ID (`repo:FonduemangVI@15520607/tech-exercise@1426612616:...`), so a deleted and recreated repo or account with the same name cannot use these identities. Set `github_oidc_subject_prefix` from `gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix`; without it the credentials use the name-based form and token exchange fails with AADSTS700213.

## Permissions

| Identity | Role | Scope | Why |
|---|---|---|---|
| `id-gh-infra` | Contributor | Subscription | Creates the environment |
| `id-gh-infra` | Resource Policy Contributor | Subscription | Contributor cannot write policy assignments |
| `id-gh-infra` | Role Based Access Control Administrator, **with a condition** | Subscription | Creates role assignments, but only for the roles in `var.assignable_roles` plus the custom command invoke role. It cannot grant Owner, User Access Administrator or RBAC Administrator. |
| `id-gh-infra` | Storage Blob Data Contributor | `tfstate` container | Read and write state |
| `id-gh-pr` | Reader | Subscription | Plan only |
| `id-gh-pr` | Storage Blob Data Contributor | `tfstate` container | Read state and take the plan lock |
| `id-gh-app` | None here | | AcrPush and AKS roles are granted in `infra/` once ACR and AKS exist |
| You | Storage Blob Data Contributor | State storage account | Run `infra/` locally if needed |

Custom role **AKS Command Invoke (tech-exercise)**: `managedClusters/read`, `runCommand/action` and `commandResults/read` only. The one built-in role with `runCommand` (AKS Cluster Admin Role) also lists the cluster admin credential. Commands run as the caller, so Kubernetes RBAC still applies. Creating it needs `roleDefinitions/write`, which the person running the bootstrap has (Owner or User Access Administrator) and the pipeline does not.

Pull requests from forks cannot request an OIDC token, so only branches in this repository can use `id-gh-pr`.

## Prerequisites

* Terraform 1.9 or later, Azure CLI, `gh` (logged in), `jq`
* Rights to create role assignments at subscription scope (Owner, or User Access Administrator plus Contributor)

## Steps

```bash
az login --tenant <tenant-id>
az account set --subscription <subscription-id>

cd infra/bootstrap
cp bootstrap.example.tfvars bootstrap.tfvars   # git-ignored; fill in
terraform init
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
terraform apply bootstrap.tfplan

cd ../..
./scripts/bootstrap-github.sh
```

`bootstrap-github.sh` creates the `prod-infra` (approval required) and `prod-app` environments, both restricted to `main`, and sets the repository variables the pipelines read.

## State

Bootstrap state is local (`infra/bootstrap/terraform.tfstate`) and git-ignored. It holds resource IDs and may include storage account attributes, so treat it as sensitive and keep a private copy until teardown.

## Teardown

Destroy `infra/` first, then this configuration:

```bash
terraform -chdir=infra/bootstrap destroy -var-file=bootstrap.tfvars
```

Delete the GitHub environments and variables afterwards if the repository is kept.
