#!/usr/bin/env bash
# One-off: installs Flux into the cluster from this machine. Afterwards Flux
# manages itself and everything under kubernetes/apps from Git.
#
# Run from the repository root after the infra apply, scripts/import-images.sh
# and scripts/set-app-vars.sh. Uses your Azure CLI login (needs Azure
# Kubernetes Service RBAC Cluster Admin, granted in infra/aks.tf, and an
# IP in admin_ip_cidrs so the API server is reachable).
#
# Requires: az, gh, kubectl, kubelogin, helm, helmfile.
#
# Creates the cluster-settings ConfigMap (flux-system) with the values that
# differ per deployment. None are secrets. Flux substitutes them into every
# Kustomization (kubernetes/flux/cluster/ks.yaml).

set -euo pipefail

REPO="${REPO:-FonduemangVI/tech-exercise}"
var() { gh variable get "$1" --repo "$REPO"; }

AKS_RESOURCE_GROUP="$(var AKS_RESOURCE_GROUP)"
AKS_NAME="$(var AKS_NAME)"
ACR_NAME="$(var ACR_NAME)"
export ACR_LOGIN_SERVER FLUX_CLIENT_ID
ACR_LOGIN_SERVER="$(var ACR_LOGIN_SERVER)"
FLUX_CLIENT_ID="$(var FLUX_CLIENT_ID)"
APP_DNS_LABEL="$(var APP_DNS_LABEL)"
APP_HOSTNAME="$(var APP_HOSTNAME)"

echo "Getting cluster credentials (Entra ID, via kubelogin)"
az aks get-credentials --resource-group "$AKS_RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

echo "Logging Helm in to $ACR_LOGIN_SERVER"
az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken |
  helm registry login "$ACR_LOGIN_SERVER" --username 00000000-0000-0000-0000-000000000000 --password-stdin

echo "Creating flux-system and cluster-settings"
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl -n flux-system create configmap cluster-settings \
  --from-literal=ACR_LOGIN_SERVER="$ACR_LOGIN_SERVER" \
  --from-literal=FLUX_CLIENT_ID="$FLUX_CLIENT_ID" \
  --from-literal=APP_DNS_LABEL="$APP_DNS_LABEL" \
  --from-literal=APP_HOSTNAME="$APP_HOSTNAME" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Flux"
helmfile --file bootstrap/helmfile/apps.yaml sync --hide-notes

echo "Done. Flux now syncs kubernetes/flux/cluster from main:"
echo "  kubectl get fluxinstance,kustomizations,helmreleases -A"
