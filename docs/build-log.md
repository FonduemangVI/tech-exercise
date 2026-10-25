# Build log

What broke while building and running this environment, why, and what changed. Each fix is merged on `main`. Most were caught by a pipeline check, a lint, a policy or a test rather than found by chance.

Started on the first real deployment (22 Oct 2026). Row 15 is local laptop setup, not the environment; the rest are in the environment or the pipelines.

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | Bootstrap region rejected | Lab policy "Allowed Locations (East US only)" | Region `eastus`, code `eus`, before anything was created |
| 2 | First plan: AADSTS700213, no matching federated identity | New repos use GitHub's immutable OIDC subjects (`repo:<owner>@<id>/<repo>@<id>`) | `github_oidc_subject_prefix` in the bootstrap |
| 3 | VNet /16 with a /22 for AKS, far larger than needed | Sized for growth that overlay CNI does not need | Right-sized to /24 (/26, /28, /28); one teardown and rebuild |
| 4 | Key Vault create failed: `SubnetsNotProvisioned` | Subnets still "Updating" from the NSG associations | `depends_on` both NSG associations |
| 5 | Activity Log setting "already exists" after the rebuild | Subscription diagnostic settings are eventually consistent after a delete | Re-ran Apply; no import needed |
| 6 | Key Vault and AKS logs in `AzureDiagnostics` | Both default to the shared table | `Dedicated` destination on those two; also removed two permanent plan diffs (blob metrics, API server subnet delegation) |
| 7 | Portal could not list backups | Shared keys off and no data-plane role for the admin; then the pipeline's role condition refused the new role | Storage Blob Data Reader on `backups`, added to `assignable_roles`; portal defaults to Entra ID |
| 8 | PR plan 403 on `listClusterUserCredential` once the cluster existed | Reader has no actions | AKS Cluster User Role for `id-gh-pr` on the cluster only |
| 9 | FluxInstance rejected: `artifact` null | Chart writes the value unquoted and the CRD requires `oci://` | Pinned the manifests artifact (ghcr.io, `v0.61.0`); images still from ACR |
| 10 | flux-operator upgrade timed out | One node 97% reserved on CPU requests | Second node |
| 11 | Envoy Gateway: "configmaps cluster-settings not found" | `substituteFrom` only reads the Kustomization's own namespace | Root Kustomization passes the values as `postBuild.substitute` |
| 12 | App deploy refused HTTPRoute and SecretProviderClass | AKS RBAC Writer has no custom resource rights; Azure has no per-CRD data actions | Custom role with `customresources/*`, assigned on `tasky` only. Later testing showed this also covers Flux objects: see OPS-4 in the [issue register](issue-register.md) |
| 13 | Envoy proxy image from docker.io (policy in Audit, so allowed) | `global.imageRegistry` does not cover the proxy | `EnvoyProxy` sets the proxy image from ACR |
| 14 | Trivy showed no MEDIUM findings (W5 hidden) | `--severity` filters the report, not only the gate | Report step (all severities) and gate step (HIGH, CRITICAL) |
| 15 | Laptop tooling: `~/.kube` owned by root; no `helmfile` version selected in mise | Local setup | `chown` the folder; `mise use -g helmfile@1.8.2` |
| 16 | Audit query in Log Analytics did not find the W3 grant | The Activity Log export only holds events from when its diagnostic setting exists; on the rebuild the setting failed first (#5) and W3 was granted before the re-run | `demo.sh` reads the Activity Log itself (90 days) and names the caller identity. Lesson: an audit pipeline must exist before the changes it audits |
| 17 | First full `demo.sh` run: noisy image list, `(exit 141)`, CLI extension prompt mid-demo | 26 MCR add-on images listed; `head` closed the pipe under `pipefail`; `log-analytics` extension not installed | Image list skips the excluded namespaces and counts them; `sed -n 1,5p`; pre-flight checks the extension |
| 18 | Defender (MCSB): encryption at host off on the VM and the AKS nodes | Not set; needs the `Microsoft.Compute/EncryptionAtHost` subscription feature | Feature registered (runbook check); `encryption_at_host_enabled` on the VM and `host_encryption_enabled` on the pool. Applied through the pipeline: VM deallocated and restarted, AKS pool rotated through a temporary pool (no cluster rebuild) |
| 19 | Apply was approved without a plan to read | One job planned and applied after the approval | Plan runs on `main` too (read-only `id-gh-pr`, federated credential for `ref:refs/heads/main`); Apply runs only when there are changes, plans again and stops unless its fingerprint (hash of address, actions and planned values) matches the reviewed plan. No plan file between jobs: it holds sensitive values and artifacts are downloadable in a public repo |
| 20 | Image scan showed HIGH and CRITICAL only; BuildKit `InvalidDefaultArgInFrom`; Docker Hub pull on every build | `--severity` filters the report; `ARG REGISTRY` had no default; `# syntax=docker/dockerfile:1` fetches the frontend from Docker Hub | Report and gate steps for the image too; `REGISTRY` defaults to `registry.invalid` (fails closed); syntax line removed |
| 21 | Trivy 0.76.0 out of date, Dependabot silent | `TRIVY_VERSION` and `TERRAFORM_VERSION` are workflow env values, which Dependabot does not read | Bumped to 0.76.1 by hand; gap noted in `dependabot.yml` |
| 22 | App pipeline rebuilt and redeployed on every merge to `main`, even a tool bump | No check for changes; image tagged with the commit SHA | Read-only `changes` job compares the commit with the last successful `prod-app` deployment over `app/` and the tasky manifests; no change, no approval asked. Content-addressed image tag: an existing image is reused and rescanned, never rebuilt (#29) |
| 23 | A base image re-imported under the same tag (`import-images.sh --force`) would not trigger a rebuild; an unchanged image was never rescanned between deploys | Tag hashed only the `app/` tree; scans ran only on deploy | Tag is now a hash of the `app/` tree and the ACR digests of the base images (#30). New `rescan.yml`: daily report and gate on the newest tasky image in ACR, read-only, failure notified by GitHub |
| 24 | Review of why plans are not passed between jobs: state (and so every plan file) holds the Log Analytics shared keys | The workspace allowed key-based ingestion, so anyone with a key could write forged records into the audit store | `local_authentication_enabled = false` on the workspace: Entra ID only. The keys stay in state but can no longer write. The plan file still is not passed as an artifact (storage keys are in state too) |

Accepted risks and the intentional weaknesses are not here: see the [issue register](issue-register.md).
