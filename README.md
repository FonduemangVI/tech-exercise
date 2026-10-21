# Wiz Technical Exercise (V4) on Azure

> **Warning: deliberately vulnerable environment.**
> This repository builds an Azure environment that contains intentional security
> weaknesses, as required by the Wiz Technical Exercise. Do not deploy it to a
> subscription that holds anything you care about, and tear it down when finished.
> Each weakness is documented in [`docs/risk-register.md`](docs/risk-register.md).

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
| `k8s/flux/` | FluxInstance, applied once at bootstrap |
| `k8s/platform/` | Platform components, owned and reconciled by Flux |
| `k8s/apps/tasky/` | Application manifests, owned and deployed by the app pipeline |
| `app/` | tasky source, Dockerfile and `wizexercise.txt` |
| `scripts/` | Helper scripts, such as importing upstream images into ACR |
| `demo/` | Scripted demo steps for the presentation |
| `docs/` | Risk register and supporting notes |
| `.github/workflows/` | `infra.yml` (IaC), `app.yml` (build, scan, push, deploy), `destroy.yml` (teardown) |

## Pipelines

| Pipeline | What it does |
|---|---|
| `infra.yml` | Format and validate Terraform, scan with Trivy, plan on pull request, apply on `main` with approval |
| `app.yml` | Build the image from ACR base images, scan with Trivy, check `wizexercise.txt`, push to ACR, deploy to AKS |
| Flux | Reconciles `k8s/platform/` from `main` (not a pipeline) |

Both pipelines authenticate to Azure with OpenID Connect (workload identity federation). No client secrets are stored.

## Deliberate weaknesses

| ID | Weakness |
|---|---|
| W1 | VM runs an outdated Linux release (Ubuntu 20.04) |
| W2 | VM runs an outdated MongoDB (6.0) |
| W3 | VM managed identity has Contributor on the subscription |
| W4 | SSH open to the internet |
| W5 | Application service account bound to `cluster-admin` |
| W6 | Backup container allows public read and public listing |

See [`docs/risk-register.md`](docs/risk-register.md) for exposure, business impact and remediation.

## Getting started

Prerequisites, bootstrap and deployment steps will be added as each part is built.

## Use of AI tools

An AI assistant was used for planning, scaffolding and review. All code has been read, tested and is understood by the author.
