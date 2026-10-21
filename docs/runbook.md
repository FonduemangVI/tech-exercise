# Runbook

Deploys the environment from an empty subscription, in order. Each step lists what it needs, what to run and how to tell it worked. Do not start a step until the previous one is done.

Run everything from the repository root unless a step says otherwise.

## 0. Before you start

**Tools on the laptop:** Terraform 1.9 or later, Azure CLI, `gh` (logged in with admin rights on the repo), `jq`, `kubectl`, `kubelogin`, `helm`, `helmfile`.

**Access:** Owner on the subscription (or User Access Administrator plus Contributor). The bootstrap creates role assignments and a custom role.

**Checks in the subscription (once):**

| Check | Command | Why |
|---|---|---|
| vCPU quota | `az vm list-usage -l <region> -o table` | 1 AKS node (2 vCPU) plus the VM (2 vCPU) need 4 |
| Ubuntu 20.04 image | `az vm image list -p Canonical -f 0001-com-ubuntu-server-focal -s 20_04-lts-gen2 -l <region> --all -o table` | W1 needs it |
| Existing policy assignments | `az policy assignment list -o table` | A tenant policy may block public blob access (W6) |

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

```bash
gh workflow run infra.yml --ref main
```

Approve the Apply job in the `prod-infra` environment. The first apply takes the longest (AKS and the VM).

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

Local Terraform access to the outputs:

```bash
cp infra/backend.example.hcl infra/backend.hcl   # git-ignored; fill in from the bootstrap outputs
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

## Day to day

| Situation | What to do |
|---|---|
| My public IP changed (`kubectl` and Key Vault access fail) | `gh secret set ADMIN_IP_CIDRS --body '["<new ip>/32"]'`, then run `infra.yml` and approve Apply |
| Platform change (Flux, cert-manager, Envoy) | PR to `kubernetes/apps`; Flux applies it after merge |
| App change | PR to `app/` or `kubernetes/apps/tasky/tasky/app/`; `app.yml` deploys after merge |
| New upstream version | Update the version in `scripts/import-images.sh` and the matching OCIRepository or HelmRelease, re-run the import, then merge |
