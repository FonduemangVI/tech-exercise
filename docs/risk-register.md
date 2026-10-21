# Risk register

These weaknesses are **intentional**, as required by the Wiz Technical Exercise (V4). They exist only in this exercise environment, are accepted for the duration of the exercise, and are removed at teardown.

Scanner findings for these items are suppressed only with an inline ignore that references the risk ID below. Any other finding fails the pipeline.

| ID | Weakness | Where | Technical exposure | Business impact | Remediation |
|---|---|---|---|---|---|
| W1 | Outdated Linux (Ubuntu 20.04) | Mongo VM | Known OS vulnerabilities with no standard patches | Breach risk; fails patching controls in audits (ISO 27001, Essential Eight, PCI DSS) | Move to a supported release; patch with Azure Update Manager; build from a maintained image |
| W2 | Outdated MongoDB (6.0, end of life) | Mongo VM | Known database vulnerabilities, no vendor fixes | Customer data at risk; no vendor support during an incident | Upgrade to a supported version, or move to a managed database on a private endpoint |
| W3 | VM managed identity has Contributor on the subscription | Mongo VM identity | Any code on the VM can manage every resource, including reading storage keys and creating VMs | Crypto-mining bill, deletion of production and backups, total outage | Remove Contributor; keep only Storage Blob Data Contributor on the backup container |
| W4 | SSH open to the internet | NSG on `snet-db` | Constant brute force; entry point for W1 to W3 | Initial access to the subscription takeover chain | Remove the public IP; use Azure Bastion or just-in-time access; SSH certificates or Entra ID login |
| W5 | App service account bound to `cluster-admin` | AKS, namespace `tasky` | A compromised internet-facing pod gains control of the whole cluster and its secrets | One vulnerable app can take down every workload | Namespaced role with no permissions; `automountServiceAccountToken: false`; workload identity for Azure access |
| W6 | Backup container allows public read and listing | Storage account, container `backups` | Full database dumps downloadable with no authentication | Notifiable data breach (Privacy Act NDB scheme, GDPR), regulator involvement, loss of customer trust | Private container, private endpoint, versioned immutable storage, separate backup subscription |

## Attack chains

| Chain | Path | Priority |
|---|---|---|
| Data breach | W6 on its own: no exploit needed | 1 |
| Subscription takeover | W4, then W1 or W2, then W3 | 2 |
| Cluster compromise | Public app, then W5, then the Mongo credentials in the cluster | 3 |

## Scanner suppressions

| Risk ID | Scanner | Check ID | File |
|---|---|---|---|
| W4 | Trivy | _to be added_ | `infra/network.tf` |
| W6 | Trivy | _to be added_ | `infra/storage.tf` |
