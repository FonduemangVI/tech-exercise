# Kubernetes manifests

Each path has exactly one owner, so Flux and the pipeline never manage the same object.

| Path | Owner | Contents |
|---|---|---|
| `flux/` | Applied once at bootstrap (laptop) | FluxInstance |
| `platform/` | Flux (reconciled from `main`) | Envoy Gateway (OCIRepository, HelmRelease), EnvoyProxy, GatewayClass, Gateway |
| `apps/tasky/` | `app.yml` pipeline | ServiceAccount (workload identity), SecretProviderClass (Key Vault to Secret `tasky-secrets`), Deployment, Service, HTTPRoute. `namespace.yaml` and `rbac.yaml` (W5) are cluster-scoped, so `scripts/bootstrap-cluster.sh` applies them once as an admin. |

If both Flux and the pipeline managed the tasky Deployment, Flux would revert the image tag set by the pipeline on its next reconcile.

All images must come from the project ACR. The Azure Policy allowed-images rule denies anything else.
