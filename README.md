# Wiz Technical Exercise (V4) on Azure

> **Warning: deliberately vulnerable environment.**
> This repository builds an Azure environment that contains intentional security
> weaknesses, as required by the Wiz Technical Exercise. Do not deploy it to a
> subscription that holds anything you care about, and tear it down when finished.
> Each weakness is documented in [`docs/issue-register.md`](docs/issue-register.md).

## What it builds

A two-tier web application on Azure:

- **Front end:** the [tasky](https://github.com/jeffthorne/tasky) todo app, rebuilt as a container image, running on AKS behind Envoy Gateway (Gateway API) and an Azure Standard Load Balancer.
- **Database:** MongoDB on an Azure VM, backed up daily to Azure Blob Storage.
- **Platform:** AKS with API Server VNet Integration, Flux Operator for platform components (GitOps), and Azure Container Registry as the only image source.
- **Security controls:** Activity Log and resource diagnostic settings sent to Log Analytics, Azure Policy (allowed images), Defender for Cloud, and Trivy scans in both pipelines.

## Repository layout

| Path | Purpose |
|---|---|
| `infra/bootstrap/` | Run once locally: Terraform state storage, GitHub OIDC identities and federated credentials |
| `infra/` | Main Terraform: network, AKS, Mongo VM, storage, ACR, monitoring, policy |
| `kubernetes/` | Cluster config, laid out like home-ops: `flux/cluster/` is the Flux root, `apps/<namespace>/<app>/` holds each app (`ks.yaml` plus `app/`). See [`kubernetes/README.md`](kubernetes/README.md) |
| `bootstrap/helmfile/` | One-off Flux install (Flux Operator, then FluxInstance), using the same chart versions and values as Git |
| `app/` | tasky source, Dockerfile and `wizexercise.txt` |
| `scripts/` | Bootstrap and helper scripts: GitHub variables, image import into ACR, app variables, Flux bootstrap |
| `demo/` | Scripted demo steps for the presentation |
| `docs/` | Runbook (deployment order), issue register, build log, architecture diagram and demo queries |
| `.github/workflows/` | `infra.yml` (IaC), `app.yml` (build, scan, push, deploy), `actions-lock.yml` (lockfile check) |

## Pipelines

| Pipeline | What it does |
|---|---|
| `infra.yml` | Format and validate Terraform, scan with Trivy, plan on pull request, apply on `main` with approval |
| `app.yml` | Build the image from ACR base images, scan with Trivy, check `wizexercise.txt`, push to ACR, deploy to AKS |
| Flux | Reconciles `kubernetes/apps/` from `main` (not a pipeline): Flux itself, cert-manager, Envoy Gateway, and the tasky namespace and W5 binding |

Both pipelines authenticate to Azure with OpenID Connect (workload identity federation). No client secrets are stored.

Action dependencies are locked to verified commits in [`.github/workflows/actions.lock`](.github/workflows/actions.lock) (GitHub workflow dependency lockfile, public preview), generated with `gh actions-lock`. The `actions-lock` workflow fails any PR whose lockfile is missing or stale. To add or change an action, edit the workflow, run `gh actions-lock`, and commit both files.

## Deliberate weaknesses

| ID | Weakness |
|---|---|
| W1 | VM runs an outdated Linux release (Ubuntu 20.04) |
| W2 | VM runs an outdated MongoDB (6.0) |
| W3 | VM managed identity has Contributor on the subscription |
| W4 | SSH open to the internet |
| W5 | Application service account bound to `cluster-admin` |
| W6 | Backup container allows public read and public listing |

See [`docs/issue-register.md`](docs/issue-register.md) for the control each one breaks, exposure, business impact and remediation.

## Getting started

Follow [`docs/runbook.md`](docs/runbook.md): prerequisites, then bootstrap, infrastructure, image import, Flux, app and controls, in that order, with a check after each step.

## Use of AI tools

An AI assistant was used for planning, scaffolding and review. All code has been read, tested and is understood by the author.
