# Infrastructure

Main Terraform for the exercise environment. Applied by `.github/workflows/infra.yml`; can also be run locally.

| File | Contents |
|---|---|
| `versions.tf` | Terraform and provider versions; partial `azurerm` backend (Entra ID auth) |
| `providers.tf` | azurerm provider; OIDC in the pipeline, Azure CLI locally |
| `variables.tf` | Subscription, region, tags, Log Analytics retention and daily cap |
| `naming.tf` | Prefix, resource names and tags used everywhere |
| `main.tf` | Resource group |
| `monitoring.tf` | Log Analytics workspace; subscription Activity Log to Log Analytics (control plane audit, R26) |
| `diagnostics.tf` | Diagnostic settings for every supported resource |

More files (network, AKS, Mongo VM, storage, ACR, policy) are added as each part is built.

## Pipeline

| Event | Job | Identity | What it does |
|---|---|---|---|
| Every PR | Static checks | none | `fmt`, `validate` (bootstrap and infra), Trivy IaC scan. Fails on HIGH or CRITICAL. |
| PR from this repo | Plan | `id-gh-pr` (read-only) | `terraform plan`, output in the job summary |
| Push to `main`, or manual run | Apply | `id-gh-infra`, via `prod-infra` environment (approval) | Plan and apply |

Plan and Apply are skipped until the bootstrap has been run and the repo variables exist.

## Local run

```bash
cp backend.example.hcl backend.hcl    # git-ignored; fill in from bootstrap outputs
cp infra.example.tfvars infra.tfvars  # git-ignored
az login
terraform init -backend-config=backend.hcl
terraform plan -var-file=infra.tfvars
```
