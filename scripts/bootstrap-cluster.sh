#!/usr/bin/env bash
# One-off cluster setup that needs cluster-wide rights, run by an admin
# (Azure Kubernetes Service RBAC Cluster Admin, granted in infra/aks.tf).
# Uses command invoke, so it works whether or not the API server is
# reachable from this machine.
#
#   AKS_RESOURCE_GROUP=<rg> AKS_NAME=<cluster> scripts/bootstrap-cluster.sh
#
# Applies:
#   k8s/apps/tasky/namespace.yaml   cluster-scoped, so app.yml cannot create it
#   k8s/apps/tasky/rbac.yaml        W5: tasky-sa bound to cluster-admin (intentional)

set -euo pipefail

: "${AKS_RESOURCE_GROUP:?}" "${AKS_NAME:?}"

cd "$(dirname "$0")/../k8s/apps/tasky"

az aks command invoke \
  --resource-group "$AKS_RESOURCE_GROUP" --name "$AKS_NAME" \
  --file namespace.yaml --file rbac.yaml \
  --command "kubectl apply -f namespace.yaml -f rbac.yaml"
