# Runbook

Deploys the environment from an empty subscription, in order. Each step lists what it needs, what to run and how to tell it worked. Do not start a step until the previous one is done.

Run everything from the repository root unless a step says otherwise.

## 0. Before you start

**Tools on the laptop:** Terraform 1.9 or later, Azure CLI, `gh` (logged in with admin rights on the repo), `jq`, `kubectl`, `kubelogin`, `helm`, `helmfile`.

**Access:** Owner on the subscription (or User Access Administrator plus Contributor). The bootstrap creates role assignments and a custom role.

**Checks in the subscription (once):**

| Check | Command | Why |
|---|---|---|
| Allowed regions | `az policy assignment list -o table` | The lab subscription allows East US only ("Allowed Locations" policy): set `location = "eastus"` in both tfvars |
| vCPU quota | `az vm list-usage -l <region> -o table` | 2 AKS nodes (2 vCPU each) plus the VM (2 vCPU) need 6, plus 2 for an upgrade surge node |
| Ubuntu 20.04 image | `az vm image list -p Canonical -f 0001-com-ubuntu-server-focal -s 20_04-lts-gen2 -l <region> --all -o table` | W1 needs it |
| Encryption at host | `az feature register --namespace Microsoft.Compute --name EncryptionAtHost`, wait for `az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state` to say `Registered` (10 to 20 minutes), then `az provider register --namespace Microsoft.Compute` | The VM and the AKS nodes set encryption at host; without the feature the apply fails |
| Existing policy assignments | `az policy assignment list -o table` | A tenant policy may block public blob access (W6). Defender for Cloud's auto-provisioning assignments may also change the cluster or the VM after apply: see "Day to day" |

**SSH key:** `~/.ssh/wiz-exercise` (ed25519, used only for this exercise). Create it if missing:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/wiz-exercise -C wiz-exercise-mongo-vm -N ''
```

## 1. Bootstrap (laptop, once)

Creates state storage, the three pipeline identities and their federated credentials, the custom command invoke role, and registers the resource providers. Details in [`infra/bootstrap/README.md`](../infra/bootstrap/README.md).

```bash
az login --tenant <tenant-id>
az account set --subscription <subscription-id>

cp infra/bootstrap/bootstrap.example.tfvars infra/bootstrap/bootstrap.tfvars   # git-ignored; fill in
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan

./scripts/bootstrap-github.sh
```

`bootstrap-github.sh` creates the `prod-infra` and `prod-app` environments, the repository variables and the `ADMIN_IP_CIDRS` secret. It uses the current public IP unless `ADMIN_IP_CIDRS` is set, e.g. `ADMIN_IP_CIDRS='["203.0.113.10/32"]'`.

**Done when:** `gh variable list` shows the `AZURE_*`, `TFSTATE_*` and `VM_SSH_PUBLIC_KEY` variables, and `gh secret list` shows `ADMIN_IP_CIDRS`.

The script makes me the required reviewer on `prod-infra` and restricts both environments to `main`. Keep `infra/bootstrap/terraform.tfstate` (git-ignored) somewhere private until teardown.

## 2. Infrastructure (pipeline)

**Review a plan first.** On `main`, the read-only Plan job runs before Apply: read its summary, then approve `prod-infra`. Apply plans again and stops if that plan differs from the reviewed one (re-run the workflow); with no changes, Apply is skipped and no approval is asked for. For the very first apply, also open a PR (any change, e.g. a doc fix) and read the plan in the Plan job's summary. On an empty state it should only create resources; stop if it destroys or changes anything. It also proves `id-gh-pr` (Reader) can plan.

Then merge the PR (if it touches `infra/**` the push starts Apply), or start Apply by hand:

```bash
gh workflow run infra.yml --ref main
```

Approve the Apply job in the `prod-infra` environment. Apply makes its own plan from the same code and inputs, so it matches the reviewed one. The first apply takes the longest (AKS and the VM).

**Optional: plan locally.** Runs as me rather than the pipeline identity, so it tests less, but needs no PR. The pipeline does not use `infra.tfvars`; this writes it from the repo variables (the admin IP is a secret and cannot be read back, so it is detected again):

```bash
cp infra/backend.example.hcl infra/backend.hcl   # git-ignored; fill in from: terraform -chdir=infra/bootstrap output tfstate
R=FonduemangVI/tech-exercise; v() { gh variable get "$1" --repo "$R"; }
cat > infra/infra.tfvars <<EOT
subscription_id         = "$(v AZURE_SUBSCRIPTION_ID)"
location                = "$(v AZURE_LOCATION)"
location_short          = "$(v AZURE_LOCATION_SHORT)"
owner_tag               = "$(v OWNER_TAG)"
admin_object_id         = "$(v ADMIN_OBJECT_ID)"
admin_ip_cidrs          = ["$(curl -fsS https://api.ipify.org)/32"]
github_pr_principal_id  = "$(v AZURE_PRINCIPAL_ID_PR)"
github_app_principal_id = "$(v AZURE_PRINCIPAL_ID_APP)"
vm_ssh_public_key       = "$(v VM_SSH_PUBLIC_KEY)"
EOT
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra plan -var-file=infra.tfvars
```

`infra.tfvars` and `backend.hcl` are git-ignored. Never apply locally while the pipeline owns the environment: use the pipeline, so every change is reviewed and logged.

**Done when:**

* The Apply job is green.
* The Mongo VM finished its first boot. It installs MongoDB, creates the users, writes the three secrets to Key Vault and takes a first backup:

  ```bash
  ssh -i ~/.ssh/wiz-exercise azureuser@<mongo_public_ip> tail -n 20 /var/log/mongo-bootstrap.log
  az keyvault secret list --vault-name <key_vault_name> --query '[].name' -o tsv
  ```

  The vault lists `mongo-admin-uri`, `mongo-app-uri` and `tasky-jwt-secret`. `<mongo_public_ip>` and `<key_vault_name>` are Terraform outputs (step 3 sets up local access to them).

* A dated blob is listed at the `backup_list_url` output, opened in a browser with no login (W6).

If the backup log says the first backup failed, cron retries at 02:00 UTC; run `sudo /usr/local/sbin/mongo-backup.sh` on the VM to retry now.

## 3. Images and app variables (laptop)

Local Terraform access to the outputs (reading outputs needs `backend.hcl` only, no `infra.tfvars`; skip the copy if step 2's local plan already made it):

```bash
cp infra/backend.example.hcl infra/backend.hcl   # git-ignored; fill in from: terraform -chdir=infra/bootstrap output tfstate
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra output
```

Copy every image and chart the cluster and the Docker builds need into ACR, then set the variables `app.yml` and the Flux bootstrap read:

```bash
ACR_NAME=<acr name, from acr_login_server without .azurecr.io> ./scripts/import-images.sh
./scripts/set-app-vars.sh
```

**Done when:** `az acr repository list --name <acr name> -o table` lists `base/*`, `fluxcd/*`, `controlplaneio-fluxcd/*`, `envoyproxy/*` and `jetstack/*`, and `gh variable list` shows `ACR_LOGIN_SERVER`, `AKS_NAME`, `FLUX_CLIENT_ID` and `APP_HOSTNAME`.

If an import from Docker Hub fails with 429 (rate limit), wait and re-run; the script is safe to repeat.

## 4. Flux (laptop, once)

**Staging certificate first.** `cloudapp.azure.com` shares one Let's Encrypt rate limit with every Azure customer, so prove the setup on staging before asking for a production certificate. In a PR, set `issuerRef.name` in `kubernetes/apps/network/envoy-gateway/config/certificate.yaml` to `letsencrypt-staging`, and merge it before running the bootstrap.

```bash
./scripts/bootstrap-flux.sh
```

It logs in to the cluster with Entra ID (`kubelogin`), creates the `cluster-settings` ConfigMap, and installs Flux Operator and the FluxInstance. From then on Flux installs everything under `kubernetes/apps` from `main`, in this order, each step waiting for the one before:

```text
envoy-gateway -> cert-manager -> cert-manager-issuers -> envoy-gateway-config
```

Watch it:

```bash
kubectl get fluxinstance -n flux-system
kubectl get kustomizations,helmreleases -A
kubectl -n network get gateway,certificate,svc
```

**Done when:**

* Every Kustomization and HelmRelease is Ready. If the chain stops, the first one that is not Ready is the problem (`kubectl describe kustomization <name> -n <namespace>`).
* The Gateway has an Azure load balancer public IP.
* Certificate `app` is Ready. `https://<APP_HOSTNAME>` then answers with an error from Envoy (no app route yet) and a browser warning (staging certificate); both are expected.

**Then switch to production, once:** a PR setting `issuerRef.name` back to `letsencrypt-production`. After merge, cert-manager issues the production certificate. Do this early and never on demo day, and do not rebuild the cluster afterwards: the certificate lives in a cluster Secret.

## 5. App (pipeline)

```bash
gh workflow run app.yml --ref main
```

The deploy job builds and scans the image, pushes it to ACR, and applies `kubernetes/apps/tasky/tasky/app/` through `az aks command invoke`.

**Done when:**

* The job is green and its log shows `deployment "tasky" successfully rolled out`.
* `https://<APP_HOSTNAME>` serves tasky with a valid certificate, and `http://` redirects to `https://`.
* A todo added in the app is visible in MongoDB.
* `kubectl exec -n tasky deploy/tasky -- cat /app/wizexercise.txt` prints the name.

## 6. Preventative control: Audit, then Deny

The allowed-images policy starts in Audit. Before switching to Deny, check that every running image comes from ACR:

```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u
```

Images outside ACR are only acceptable in the namespaces the policy excludes (`kube-system`, `gatekeeper-system`, `azure-arc`, `azure-extensions-usage-system`, `aks-command`; see `infra/policy.tf`). Then:

```bash
gh variable set POLICY_ALLOWED_IMAGES_EFFECT --body Deny
gh workflow run infra.yml --ref main   # approve Apply
```

**Done when:** `kubectl run test --image=docker.io/library/nginx -n tasky` is denied (the policy add-on syncs on its own schedule, so allow some time after the apply), and `az aks command invoke` still works (the app pipeline uses it).

## 7. Lock down the repository

Once each check has run at least once, add it as a required status check on `main`: `Static checks`, `Plan`, `Verify actions lockfile`, `Scan manifests`, `Build and scan image`.

## 8. Before the presentation

`demo/demo.sh check` before every rehearsal and before the call. The run sheet and talk track are in [`demo/README.md`](../demo/README.md).

## Cost

US$200 limit per candidate, set by CloudLabs. It emails at 50%, 80% and 100% of the limit, and **at 100% the lab is terminated** unless the recruiter has approved an extension. Ask for an extension before reaching 80%, not after. Estimated from Azure retail prices for East US (checked 22 Oct 2026; the bill may differ):

| Item | Per day |
|---|---|
| 2 AKS nodes `Standard_D2s_v5` ($0.096/h each) | $4.60 |
| Mongo VM `Standard_B2s` ($0.0416/h) | $1.00 |
| Standard Load Balancer ($0.025/h) | $0.60 |
| 3 Standard public IPs ($0.005/h each) | $0.36 |
| Disks (2 AKS OS disks, VM disk) | $0.60 |
| ACR Basic | $0.17 |
| **Fixed, running** | **about $7.35** |
| Log Analytics ingestion ($2.30/GB, capped at `law_daily_quota_gb`, default 1) | up to $2.30 |

Running all the time, with logs at the cap, this lasts about 3 weeks. Stopped between sessions it drops to about $1.55 a day (load balancer, IPs, disks and ACR keep charging). Stop, do not destroy: a rebuild costs time, uses up the shared Let's Encrypt limit and loses the certificate and the backup history.

```bash
# stop
az aks stop -g <resource_group_name> -n <aks_name>
az vm deallocate -g <resource_group_name> -n "$(az vm list -g <resource_group_name> --query '[0].name' -o tsv)"
# start, then demo/demo.sh check
az aks start -g <resource_group_name> -n <aks_name>
az vm start -g <resource_group_name> -n "$(az vm list -g <resource_group_name> --query '[0].name' -o tsv)"
```

After the first day, check what the logs cost (Log Analytics, Logs):

```kql
Usage | where TimeGenerated > ago(1d) | summarize GB = sum(Quantity) / 1000 by DataType | order by GB desc
```

If AKS audit logs dominate, lower `law_daily_quota_gb`.

## Day to day

| Situation | What to do |
|---|---|
| My public IP changed (`kubectl` and Key Vault access fail) | `gh secret set ADMIN_IP_CIDRS --body '["<new ip>/32"]'`, then run `infra.yml` and approve Apply |
| Platform change (Flux, cert-manager, Envoy) | PR to `kubernetes/apps`; Flux applies it after merge |
| App change | PR to `app/` or `kubernetes/apps/tasky/tasky/app/`; `app.yml` deploys after merge |
| `plan` shows changes nobody made to the AKS cluster (Defender profile) or the VM (identity, extensions) | Defender for Cloud's auto-provisioning policies changed them. Decide per item: bring it into Terraform, or add `ignore_changes`; do not let each apply undo it |
| New upstream version | Update the version in `scripts/import-images.sh` and the matching OCIRepository or HelmRelease, re-run the import, then merge |
