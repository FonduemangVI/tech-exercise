# Issue register

Known control failures in this environment. Each entry is an **issue**: a weakness that exists now, not a risk with a likelihood still to be assessed. There is no likelihood and impact scoring and no risk matrix behind it. The fix order comes from the attack chains below, ranked by business impact.

The W items are **intentional**, as required by the Wiz Technical Exercise (V4). They exist only in this exercise environment, stay open for the duration of the exercise, and are removed at teardown.

Scanner findings for these items are suppressed only with an inline ignore next to the resource, which references the issue ID below. The only other suppressions are for exposure the brief requires (the public web app). Any other finding fails the pipeline.

## Control failures

| ID | Issue | Control that failed | Where | Technical exposure | Business impact | Remediation | Status |
|---|---|---|---|---|---|---|---|
| W1 | Outdated Linux (Ubuntu 20.04) | Vulnerability and patch management: supported operating systems only | Mongo VM | Known OS vulnerabilities with no standard patches | Breach risk; fails patching controls in audits (ISO 27001, Essential Eight, PCI DSS) | Move to a supported release; patch with Azure Update Manager; build from a maintained image | Open (required by the brief) |
| W2 | Outdated MongoDB (6.0, end of life) | Vulnerability and patch management: supported software only | Mongo VM | Known database vulnerabilities, no vendor fixes | Customer data at risk; no vendor support during an incident | Upgrade to a supported version, or move to a managed database on a private endpoint | Open (required by the brief) |
| W3 | VM managed identity has Contributor on the subscription | Least privilege: identities | Mongo VM identity | Any code on the VM can manage every resource, including reading storage keys, creating VMs and opening the Key Vault firewall; it already holds Secrets Officer on the vault for the Mongo credentials | Crypto-mining bill, deletion of production and backups, total outage | Remove Contributor; keep only Storage Blob Data Contributor on the backup container | Open (required by the brief) |
| W4 | SSH open to the internet | Network access control: no management ports exposed to the internet | NSG on `snet-db` | Constant brute force; entry point for W1 to W3 | Initial access to the subscription takeover chain | Remove the public IP; use Azure Bastion or just-in-time access; SSH certificates or Entra ID login | Open (required by the brief) |
| W5 | App service account bound to `cluster-admin` | Least privilege: workloads | AKS, namespace `tasky` | A compromised internet-facing pod gains control of the whole cluster and its secrets | One vulnerable app can take down every workload | Namespaced role with no permissions; `automountServiceAccountToken: false`; workload identity for Azure access | Open (required by the brief) |
| W6 | Backup container allows public read and listing | Data protection: no anonymous access to data stores | Storage account, container `backups` | Full database dumps downloadable with no authentication | Notifiable data breach (Privacy Act NDB scheme, GDPR), regulator involvement, loss of customer trust | Private container, private endpoint, versioned immutable storage, separate backup subscription | Open (required by the brief) |

## Attack chains and fix order

| Fix order | Chain | Path |
|---|---|---|
| 1 | Data breach | W6 on its own: no exploit needed |
| 2 | Subscription takeover | W4, then W1 or W2, then W3 |
| 3 | Cluster compromise | Public app, then W5, then the Mongo credentials synced from Key Vault into a Kubernetes Secret |

## Accepted exceptions

Not part of the exercise brief. These are deliberate departures from a control in the supporting platform, each with compensating controls and an expiry date.

| ID | Exception | Where | Why accepted | Compensating controls | Expires | Proper fix |
|---|---|---|---|---|---|---|
| OPS-1 | State storage account public endpoint allows all networks (Trivy AZU-0012, CRITICAL) | `infra/bootstrap/main.tf` | GitHub-hosted runners have no fixed IPs, so a default-deny network rule would block the pipeline from its own state | Entra ID only (shared keys disabled), no anonymous access, TLS 1.2, RBAC scoped to the `tfstate` container, versioning and soft delete | 2026-12-31 | Private endpoint with a self-hosted runner in the VNet |
| OPS-2 | Key Vault has a public endpoint (no private endpoint) | `infra/keyvault.tf` | Keeps the design simple and within budget; the pipeline only manages the vault through Azure Resource Manager and never needs data plane access | Firewall default Deny (admin IP and the AKS and DB subnets through service endpoints only), Azure RBAC with per-identity data plane roles, no secret values in Terraform, purge protection, AuditEvent logs to Log Analytics | 2026-12-31 | Private endpoint in the VNet, public network access disabled, secret roles scoped per secret |

## Scanner suppressions

Each suppression is an inline `#trivy:ignore:<ID>` comment directly above the resource, next to a comment naming the issue or exception ID. Suppressions for accepted exceptions carry an expiry date (`:exp:YYYY-MM-DD`), after which the pipeline fails again.

| Issue ID | Scanner | Check ID | File |
|---|---|---|---|
| OPS-1 | Trivy | AZU-0012 (expires 2026-12-31) | `infra/bootstrap/main.tf` |
| W4 | Trivy | AZU-0047, AZU-0050 | `infra/network.tf` |
| R5, R18 (by design) | Trivy | AZU-0047: HTTP and HTTPS from the internet to the AKS subnet, the public entry for the web app (80 redirects to 443) | `infra/network.tf` |
| W6 | Trivy | AZU-0007 (container public access), AZU-0012 (storage network allows all) | `infra/storage.tf` |
| W5 | Trivy | KSV-0111 is MEDIUM, below the HIGH gate, so no suppression; it stays visible in every `app.yml` run | `kubernetes/apps/tasky/rbac.yaml` |
