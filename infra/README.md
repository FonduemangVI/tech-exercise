# Infrastructure

Main Terraform for the exercise environment. Applied by `.github/workflows/infra.yml`; can also be run locally.

| File | Contents |
|---|---|
| `versions.tf` | Terraform and provider versions; partial `azurerm` backend (Entra ID auth) |
| `providers.tf` | azurerm provider; OIDC in the pipeline, Azure CLI locally |
| `variables.tf` | Subscription, region, tags, admin identity and IP allow list, Log Analytics retention and daily cap |
| `naming.tf` | Prefix, resource names and tags used everywhere |
| `main.tf` | Resource group |
| `monitoring.tf` | Log Analytics workspace; subscription Activity Log to Log Analytics (control plane audit, R26) |
| `network.tf` | VNet `10.10.0.0/16`; `snet-aks`, delegated `snet-apiserver`, `snet-db` (all private subnets, no default outbound access); NSGs: Mongo 27017 from `snet-aks` only, SSH from the internet (W4), 80 and 443 to the cluster load balancer (80 only redirects and answers ACME challenges) |
| `keyvault.tf` | Key Vault for all secrets: RBAC only, firewall default Deny, purge protection; admin gets Key Vault Reader |
| `diagnostics.tf` | Diagnostic settings for every supported resource; NSGs with explicit categories (no metrics) |

More files (network, AKS, Mongo VM, storage, ACR, policy) are added as each part is built.

## Pipeline

| Event | Job | Identity | What it does |
|---|---|---|---|
| Every PR | Static checks | none | `fmt`, `validate` (bootstrap and infra), Trivy IaC scan. Fails on HIGH or CRITICAL. |
| PR from this repo | Plan | `id-gh-pr` (read-only) | `terraform plan`, output in the job summary |
| Push to `main`, or manual run | Apply | `id-gh-infra`, via `prod-infra` environment (approval) | Plan and apply |

Plan and Apply are skipped until the bootstrap has been run and the repo variables exist. They also need the `ADMIN_IP_CIDRS` repo secret (set by `scripts/bootstrap-github.sh`).

## Secrets

Terraform never writes secret values. The Mongo VM generates its own credentials at first boot and writes them to Key Vault with its managed identity; AKS reads them through the Secrets Store CSI driver with workload identity. Nothing secret lands in state, VM custom data or pipeline logs. The vault has a public endpoint (no private endpoint in this design), accepted as OPS-2 in `docs/risk-register.md`.

## Local run

```bash
cp backend.example.hcl backend.hcl    # git-ignored; fill in from bootstrap outputs
cp infra.example.tfvars infra.tfvars  # git-ignored
az login
terraform init -backend-config=backend.hcl
terraform plan -var-file=infra.tfvars
```
