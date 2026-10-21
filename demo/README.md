# Demo

`demo.sh` runs every command shown in the presentation. Each step prints the command, waits for Enter, then runs it. Nothing is typed live.

**Status: draft.** Written before the lab existed. Steps marked "lab check" in `demo.sh` (the MongoDB query and the two Log Analytics queries) have not been run against the live environment. Finalise during rehearsal 1: fix commands, trim output, time each demo.

## Before the call

1. `demo/demo.sh check`: Azure and GitHub logins, Terraform outputs, API server reachable from my IP, app answers on HTTPS, SSH to the VM, every running image from ACR. Fix any FAIL first (a changed public IP is the likely one: see `docs/runbook.md`, day to day).
2. Browser tabs open, in this order: app, GitHub Actions (latest `app.yml` run), Log Analytics Logs, Monitor > Alerts, Defender for Cloud recommendations.
3. Terminal: large font, dark theme, the window shared rather than the whole screen.
4. Screenshots of every step in the hidden backup section of the slides, in case the environment or the network fails.

## Run sheet (45 minutes)

| Min | Segment | What |
|---|---|---|
| 0-3 | Slides 1-2 | Who I am; the diagram |
| 3-8 | Slides 3-4 | How I built it; challenges and what I changed |
| 8-18 | **Demo 1** | `demo/demo.sh 1`, then the GitHub Actions tab |
| 18-25 | Slides 5-6 | Six weaknesses and their business impact; how they chain |
| 25-33 | **Demo 2** | `demo/demo.sh 2`, then the alert and Defender tabs |
| 33-37 | Slides 7-8 | Controls; what I would fix first and why |
| 37-45 | Questions | |

**Cut list if running late, in order:** GitHub Actions tab becomes a screenshot; skip `audit_role_assignments` (say what it shows); alert as a screenshot; Defender as a screenshot.

## Demo 1: it is built and it works (8-18)

| Step | Proves | Say |
|---|---|---|
| `kubectl get nodes -o wide` | R14 | No external IP on the node: the cluster sits in a private subnet. The API server is inside the VNet too (VNet integration). |
| `get fluxinstance`, `get kustomizations,helmreleases` | R2 | The platform is installed by Flux from Git. Nobody runs `helm install` by hand. |
| `get gateway,certificate,svc`, `get httproute` | R5, R18 | Kubernetes ingress through Gateway API, behind an Azure Standard Load Balancer, with a Let's Encrypt certificate. |
| `curl -sI http://...` | | Port 80 only redirects to HTTPS. |
| Browser: sign up, add a todo | R1 | The two-tier app working end to end. |
| `cat /app/wizexercise.txt` | R16 | The file is in the image and in the running container. It is copied in the Dockerfile and checked in the pipeline before push. |
| `env_sources` | R15 | `MONGODB_URI` reaches the app as an env var, from a Secret synced from Key Vault. No secret in Git, in the pipeline or in Terraform state. |
| `mongo_todos` | R6, R20 | The todo I just added is in MongoDB on the VM. Note I could SSH in from here: that is W4, coming up. |
| `images` | | Every image comes from ACR. The policy in Demo 2 enforces this. |
| `backup_list` | R12, W6 | Dated daily backups, listed with no credentials. Anyone on the internet can do this. (This also triggers the alert in Demo 2.) |
| GitHub Actions tab | R22-R25 | Two pipelines, OIDC with no stored secrets, Trivy gates on IaC, manifests and the image. |

## Demo 2: weaknesses and controls (25-33)

| Step | Shows | Say |
|---|---|---|
| `auth can-i --list` | W5 | The app's service account can do anything: `*` on `*`. |
| `can-i get secrets --all-namespaces` | W5 | Including every Secret in the cluster, such as the Mongo connection string (keys shown, not values). One app bug becomes a cluster compromise. |
| `vm_roles` | W3 | The VM identity is Contributor on the whole subscription. With W4 (SSH open) and W1/W2 (outdated OS and database), one compromised VM controls everything. |
| `audit_role_assignments` | R26, audit | Every change is attributable: the pipeline identity created that role assignment, from a reviewed PR. |
| `kubectl run ... docker.io/library/nginx` | R27, preventative | Denied: only images from my ACR may run. It does not fix W5; admission control and RBAC are separate layers. |
| `anonymous_reads`, then Alerts tab | R28, detective | The listing from Demo 1 shows up in the storage logs, and the alert has fired. The brief needs the bucket public, so the control is knowing within minutes. |
| Defender tab | | Separate findings for the VM, storage and the cluster. Nothing links them into the chains I just showed: that is the gap a graph-based tool like Wiz closes. |
