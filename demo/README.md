# Demo

`demo.sh` runs every command shown in the presentation. Each step prints the command, waits for Enter, then runs it. Nothing is typed live.

**Status:** run end to end against the lab on 22 Oct 2026. Time each demo in rehearsal 1.

## Before the call

1. `demo/demo.sh check`, about 20 minutes before the call: Azure and GitHub logins, the `log-analytics` CLI extension, Terraform outputs, API server reachable from my IP, app answers on HTTPS, SSH to the VM, every image outside the excluded namespaces from ACR. Fix any FAIL first (a changed public IP is the likely one: see `docs/runbook.md`, day to day). Then run `backup_list` once (or `demo/demo.sh 1` up to that step), so a W6 alert from that morning is already showing in Demo 2: storage logs and the alert lag the listing by up to 10 minutes.
2. Browser tabs open, in this order: app; GitHub (repo, a merged PR, the latest `infra.yml` and `app.yml` runs on `main`, the gate-fail PR); Monitor > Alerts; Defender for Cloud recommendations (or Policy > Compliance). The app URL ready to paste into the chat.
3. Terminal: large font, dark theme, the window shared rather than the whole screen.
4. Screenshots of every step in the hidden backup section of the slides, in case the environment or the network fails.

## Run sheet (60 minutes)

Format from the hiring manager: a full hour, 10 to 15 minutes of slides, then the demo. The lead panellist usually pauses with 5 minutes to go. Weighting is 60 to 70% technical, 30 to 40% presentation. Most time goes on DevSecOps and CI/CD: why each check matters, and how a change moves through the pipelines. Pitch high level first, then go deep. Check in with the panel after every segment.

| Min | Segment | What |
|---|---|---|
| 0-2 | Opening | Who I am. Check in: "Anything you want me to spend more time on?" |
| 2-14 | Slides (about 6) | The diagram; how I built it and how I used AI; the pipeline design; six weaknesses and how they chain; controls and what I would fix first |
| 14-22 | **Demo 1** | `demo/demo.sh 1`: it is built and it works. Check in |
| 22-37 | **Pipeline walkthrough** | GitHub, not the terminal: a change from PR to production, and the gate failing on a bad change (below). Check in |
| 37-47 | **Demo 2** | `demo/demo.sh 2`: weaknesses, then the control for each; alert and Defender tabs. Check in |
| 47-50 | Close | What I would fix first and why; what Wiz adds |
| 50-60 | Questions | Pause at 55 if asked |

**Cut list if running late, in order:** Defender as a screenshot; alert as a screenshot; skip `audit_role_assignments` (say what it shows); in the pipeline walkthrough, show the finished gate-fail run instead of pushing live. Never cut the pipeline walkthrough itself.

## Demo 1: it is built and it works (14-22)

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
| `images` | | Every image comes from ACR. The count at the end is AKS's own add-ons, from Microsoft's registry, in the namespaces the policy excludes. The policy in Demo 2 enforces this. |
| `backup_list` | R12, W6 | Dated daily backups, listed with no credentials. Anyone on the internet can do this. (This also triggers the alert in Demo 2.) |

## Pipeline walkthrough (22-37)

Use GitHub in the browser: tabs open on the repo, a merged PR, its runs, and the gate-fail PR.

**Before the call:** a draft PR from branch `demo/gate-fail`, never merged, that sets `privileged: true` and `allowPrivilegeEscalation: true` in the tasky container's `securityContext` (`kubernetes/apps/tasky/tasky/app/deployment.yaml`). Checked locally: the manifest gate fails with KSV-0017 (HIGH). Push it about 30 minutes before so a failed run exists; push one more empty commit live (`git commit --allow-empty`) if there is time to watch it run (about a minute).

| Step | Show | Say |
|---|---|---|
| 1 | The two workflows side by side: `infra.yml` (static, plan, apply) and `app.yml` (manifests, build, deploy) | Two pipelines because infrastructure and app change at different rates and need different rights. Same shape: check, then plan or build, then a gated deploy |
| 2 | A merged PR's checks | Every PR runs the same checks before review: Terraform fmt and validate, ShellCheck, Trivy on the IaC, the manifests and the image, and the actions lockfile. Required checks in the ruleset: nothing merges red |
| 3 | Trivy report then gate | Report shows every finding, gate fails on HIGH and CRITICAL. Deliberate weaknesses are suppressed only inline, next to the resource, naming the issue ID; accepted exceptions carry an expiry date, after which the pipeline fails again |
| 4 | Gate-fail PR | A privileged container fails the manifest gate, and Build never runs: the cheapest place to stop it. Nothing reaches the registry |
| 5 | OIDC and the three identities | No stored cloud secret anywhere. PRs get a read-only identity; only `main`, through an approved environment, gets one that can change Azure. The infra identity can only grant an allow-list of roles |
| 6 | An infra run on `main`: Plan, approval, Apply | Plan runs after merge with read-only rights and is what I approve. Apply plans again and refuses unless its fingerprint matches the reviewed plan. No changes, no approval asked |
| 7 | An app run on `main`: check for changes, then build, scan, push, deploy | A read-only job compares the commit with the last successful deployment: a tool bump deploys nothing and asks for no approval. The image tag is a hash of its build inputs (the app source and the base image digests), so the same inputs are never rebuilt or restarted, and a patched base image re-imported under the same tag triggers a rebuild, and a manifest-only change reuses the image (rescanned first: new CVEs still block it). Same gate before push; deploy runs through `command invoke` as an identity limited to the `tasky` namespace. Between deploys, `rescan.yml` reruns the same gate every day on the newest image with that day's vulnerability data: new CVEs in an unchanged image fail a run and GitHub notifies me |
| 8 | Supply chain | Actions locked to verified commits; Trivy downloaded with a checksum; base images only from ACR; Dependabot PRs go through the same checks (and what it misses: tool versions) |
| 9 | How it was built | Written with AI help and reviewed line by line; the build log shows where the first version was wrong (severity filter hiding findings, the Docker Hub pull) and the pipeline or a lint caught it |

## Demo 2: weaknesses and controls (37-47)

| Step | Shows | Say |
|---|---|---|
| `auth can-i --list` | W5 | The app's service account can do anything: `*` on `*`. |
| `can-i get secrets --all-namespaces` | W5 | Including every Secret in the cluster, such as the Mongo connection string (keys shown, not values). One app bug becomes a cluster compromise. |
| `vm_roles` | W3 | The VM identity is Contributor on the whole subscription. With W4 (SSH open) and W1/W2 (outdated OS and database), one compromised VM controls everything. |
| `audit_role_assignments` | R26, audit | Every change is attributable: the infra pipeline identity created the W3 grant, from a reviewed PR, at this time. It reads the Activity Log itself: the Log Analytics copy only starts when its diagnostic setting was created, and the rebuild granted W3 just before that (a gap worth admitting if asked). |
| `kubectl run ... docker.io/library/nginx` | R27, preventative | Denied: only images from my ACR may run. It does not fix W5; admission control and RBAC are separate layers. |
| `anonymous_reads`, then Alerts tab | R28, detective | The anonymous listings show up in the storage logs with the caller's IP, and the alert has fired. The brief needs the bucket public, so the control is knowing within minutes. The listing from Demo 1 may still be in transit (a few minutes); the morning's one will be there. Each listing fires two alerts: the 10-minute window overlaps the 5-minute schedule so late logs are not missed. |
| Defender tab | | Separate findings for the VM, storage and the cluster. Nothing links them into the chains I just showed: that is the gap a graph-based tool like Wiz closes. |

**Defender (free tier) against the weaknesses.** From the Microsoft cloud security benchmark policy results on 22 Oct 2026 (Defender's Recommendations page fills from these, up to 24 hours after resources are created; if it is still empty, show Policy > Compliance > Microsoft cloud security benchmark instead):

| Weakness | Flagged? | Finding |
|---|---|---|
| W1 Ubuntu 20.04 | Indirectly | "System updates should be installed", "Linux machines should meet the Azure compute security baseline"; nothing says the OS is end of life |
| W2 MongoDB 6.0 | No | No agent or paid plan to inventory software |
| W3 VM identity Contributor on the subscription | No | Nothing on over-privileged managed identities |
| W4 SSH open to the internet | Yes | "Management ports should be closed", "...protected with just-in-time network access" |
| W5 cluster-admin binding | Partly | "Kubernetes clusters should disable automounting API credentials"; nothing on the binding itself |
| W6 public backups | Yes | "Storage account public access should be disallowed" |

Say: two of six are caught directly, each one on its own. None of them is linked to the others, so the chains (W4 to W1 to W3, app to W5 to secrets) are invisible. Some VM findings say the opposite of what was built: "Authentication to Linux machines should require SSH keys" is non-compliant although password login is off, because that check needs the Guest Configuration agent, which is not installed. Compliance results need reading, not counting.
