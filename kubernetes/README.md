# Kubernetes

Laid out like [home-ops](https://github.com/FonduemangVI/home-ops): one folder per namespace, one folder per app, and a Flux `Kustomization` (`ks.yaml`) pointing at each app's `app/` folder.

```text
kubernetes/
├── flux/cluster/ks.yaml          # root: reconciles everything under apps/
└── apps/
    ├── flux-system/              # Flux manages itself
    │   ├── flux-operator/        # ks.yaml + app/ (HelmRelease, OCIRepository)
    │   └── flux-instance/        # FluxInstance: 3 controllers, images from ACR
    ├── cert-manager/
    │   └── cert-manager/         # app/: HelmRelease; issuers/: Let's Encrypt ClusterIssuers (HTTP-01)
    ├── network/
    │   └── envoy-gateway/        # app/: HelmRelease (installs the CRDs); config/: EnvoyProxy, GatewayClass, Gateway, redirect, Certificate
    └── tasky/
        ├── namespace.yaml        # Flux
        ├── rbac.yaml             # Flux: W5, cluster-admin binding (intentional)
        └── tasky/app/            # app.yml pipeline: no ks.yaml, Flux never touches it
```

## Who owns what

Each object has exactly one owner, so Flux and the pipeline never fight over it.

| Path | Owner | Why |
|---|---|---|
| `apps/flux-system/`, `apps/cert-manager/`, `apps/network/` | Flux | Platform components, cluster-wide |
| `apps/tasky/namespace.yaml`, `apps/tasky/rbac.yaml` | Flux | Cluster-scoped: the app pipeline only has rights inside `tasky` |
| `apps/tasky/tasky/app/` | `app.yml` | R23: the pipeline deploys the image it built. No `ks.yaml`, and Flux does not descend into a folder that has its own `kustomization.yaml` |

## Order

CRDs come from the Helm charts, so a resource that uses them must sit in a separate Flux `Kustomization` that waits for the chart. That is why cert-manager and envoy-gateway each have a second folder (same pattern as `tuppr/upgrades` in home-ops):

```text
envoy-gateway          HelmRelease: Gateway API + Envoy CRDs
  └─ cert-manager      HelmRelease: needs the Gateway API CRDs at startup
       └─ cert-manager-issuers   ClusterIssuers, healthy once Ready
            └─ envoy-gateway-config   EnvoyProxy, Gateway, redirect, Certificate
```

All HelmReleases use `crds: CreateReplace` (set in `flux/cluster/ks.yaml`), so CRDs are upgraded with the chart.

## Per-deployment values

Names that change per environment (registry, client ID, hostname) are not in Git. `scripts/bootstrap-flux.sh` writes them to the `cluster-settings` ConfigMap in `flux-system`, and the root Kustomization substitutes them into every app: `${ACR_LOGIN_SERVER}`, `${FLUX_CLIENT_ID}`, `${APP_DNS_LABEL}`, `${APP_HOSTNAME}`. None are secrets.

## Images

Every image and chart comes from ACR (`scripts/import-images.sh`). Charts are pulled by source-controller with workload identity (`id-flux`, AcrPull); the FluxInstance uses the manifests built into the operator, so nothing is downloaded from ghcr.io at runtime. The allowed-images policy denies anything else.

## Bootstrap

Once, after the infra apply, image import and `scripts/set-app-vars.sh`:

```bash
scripts/bootstrap-flux.sh
```

It installs Flux Operator and the FluxInstance with helmfile (same versions and values as Git). From then on Flux reconciles `kubernetes/flux/cluster` from `main`, and everything else, CRDs included, comes from Flux.
