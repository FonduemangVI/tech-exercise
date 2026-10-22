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
| `network.tf` | VNet `10.10.0.0/24` (`snet-aks` /26, `snet-apiserver` /28, `snet-db` /28); `snet-aks`, delegated `snet-apiserver`, `snet-db` (all private subnets, no default outbound access); NSGs: Mongo 27017 from `snet-aks` only, SSH from the internet (W4), 80 and 443 to the cluster load balancer (80 only redirects and answers ACME challenges) |
| `mongo_vm.tf` | Mongo VM: Ubuntu 20.04 (W1), MongoDB 6.0 (W2), Contributor on the subscription (W3), public IP; SSH key only, Trusted Launch, static private IP `10.10.0.90`; Storage Blob Data Contributor on `backups` and Key Vault Secrets Officer |
| `vm/` | cloud-init template and the scripts it installs: `kv.sh` (Key Vault and Blob REST helpers using the VM identity), `mongo-bootstrap.sh` (first boot: install MongoDB, create users, store credentials in Key Vault, enable auth), `mongo-backup.sh` (daily dump to blob) |
| `storage.tf` | Backup storage account (no shared keys, TLS 1.2, soft delete) and the `backups` container with anonymous read and list (W6) |
| `acr.tf` | Container registry (Basic, admin user off, Entra ID only); AcrPull for `id-gh-pr`, AcrPush for `id-gh-app` |
| `aks.tf` | AKS: two nodes, CNI Overlay with Cilium, API Server VNet Integration with the admin IP allow list, Entra ID and Azure RBAC with local accounts off, OIDC issuer and workload identity, Azure Policy and Secrets Store CSI add-ons; `id-aks` with Network Contributor on its subnets; cluster access for me and namespace-only access for `id-gh-app` |
| `workload_identity.tf` | `id-flux` (AcrPull, for Flux source-controller) and `id-tasky` (Key Vault Secrets User), each with a federated credential for one service account |
| `policy.tf` | R27: built-in "allowed images" policy on the cluster, ACR only (Audit, then Deny via the `POLICY_ALLOWED_IMAGES_EFFECT` repo variable); `aks-command` excluded so `command invoke` keeps working |
| `alerts.tf` | R28: one alert on anonymous reads of the backups (W6), shown in the portal. Demo queries are in `docs/queries.md` |
| `keyvault.tf` | Key Vault for all secrets: RBAC only, firewall default Deny, purge protection; admin gets Key Vault Reader |
| `diagnostics.tf` | Diagnostic settings for every supported resource; NSGs with explicit categories (no metrics) |


## Pipeline

| Event | Job | Identity | What it does |
|---|---|---|---|
| Every PR | Static checks | none | `fmt`, `validate` (bootstrap and infra), ShellCheck (VM and repo scripts), Trivy IaC scan. Fails on HIGH or CRITICAL. |
| PR from this repo | Plan | `id-gh-pr` (read-only) | `terraform plan`, output in the job summary |
| Push to `main`, or manual run | Apply | `id-gh-infra`, via `prod-infra` environment (approval) | Plan and apply |

Plan and Apply are skipped until the bootstrap has been run and the repo variables exist. They also need the `ADMIN_IP_CIDRS` repo secret and the `VM_SSH_PUBLIC_KEY`, `AZURE_PRINCIPAL_ID_APP` and `AZURE_PRINCIPAL_ID_PR` repo variables (all set by `scripts/bootstrap-github.sh`).

AKS upgrades: automatic Kubernetes upgrades are off for the life of the exercise and node OS patches apply in place (`Unmanaged`), so nothing changes under the demo. (Planned for a 4 vCPU quota, where the surge node an upgrade needs would not fit; the lab allows 50, but fewer moving parts still wins.)

## Secrets

Terraform never writes secret values. The Mongo VM generates its own credentials at first boot and writes them to Key Vault with its managed identity; AKS reads them through the Secrets Store CSI driver with workload identity. Nothing secret lands in state, VM custom data or pipeline logs.

Changing any file in `vm/` changes the VM's custom data, which replaces the VM (new disk, empty database). The bootstrap script reuses the passwords already in Key Vault, so the app's connection string stays valid. The vault has a public endpoint (no private endpoint in this design), accepted as exception OPS-2 in `docs/issue-register.md`.

## Local run

```bash
cp backend.example.hcl backend.hcl    # git-ignored; fill in from bootstrap outputs
cp infra.example.tfvars infra.tfvars  # git-ignored
az login
terraform init -backend-config=backend.hcl
terraform plan -var-file=infra.tfvars
```
