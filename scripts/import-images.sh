#!/usr/bin/env bash
# Copies upstream images into ACR with az acr import (server-side copy, no
# local pull or push). ACR is the only image source for the cluster and for
# Docker build base images.
#
# Run from a machine logged in to Azure with AcrPush (or Contributor) on
# the registry. Safe to re-run: --force overwrites an existing tag.
#
#   ACR_NAME=<registry name> scripts/import-images.sh
#
# Docker Hub rate limits anonymous pulls; if an import fails with 429,
# retry later or pass --username/--password for a Docker Hub account.

set -euo pipefail

: "${ACR_NAME:?set ACR_NAME to the registry name (not the login server)}"

import() { # $1 = source image, $2 = target repository:tag in ACR
  echo "Importing $1 -> $2"
  az acr import --name "$ACR_NAME" --source "$1" --image "$2" --force --only-show-errors
}

# Build base images for app/Dockerfile
GO_TAG="1.26-alpine3.24"
ALPINE_TAG="3.24"
import "docker.io/library/golang:${GO_TAG}" "base/golang:${GO_TAG}"
import "docker.io/library/alpine:${ALPINE_TAG}" "base/alpine:${ALPINE_TAG}"

# Platform versions. Keep in step with the OCIRepository tags under
# kubernetes/apps and the Flux version in flux-instance's HelmRelease.
FLUX_OPERATOR_VERSION="0.61.0"      # chart tag; image tag is v0.61.0
FLUX_SOURCE_CONTROLLER="v1.9.6"     # Flux 2.9.6, embedded in flux-operator 0.61.0
FLUX_KUSTOMIZE_CONTROLLER="v1.9.6"
FLUX_HELM_CONTROLLER="v1.6.5"
ENVOY_GATEWAY_VERSION="v1.9.2"      # chart and controller
ENVOY_PROXY_TAG="distroless-v1.39.1" # default proxy image of gateway-helm v1.9.2
CERT_MANAGER_VERSION="v1.21.2"

# Flux Operator and Flux controllers
import "ghcr.io/controlplaneio-fluxcd/charts/flux-operator:${FLUX_OPERATOR_VERSION}" "controlplaneio-fluxcd/charts/flux-operator:${FLUX_OPERATOR_VERSION}"
import "ghcr.io/controlplaneio-fluxcd/charts/flux-instance:${FLUX_OPERATOR_VERSION}" "controlplaneio-fluxcd/charts/flux-instance:${FLUX_OPERATOR_VERSION}"
import "ghcr.io/controlplaneio-fluxcd/flux-operator:v${FLUX_OPERATOR_VERSION}" "controlplaneio-fluxcd/flux-operator:v${FLUX_OPERATOR_VERSION}"
import "ghcr.io/fluxcd/source-controller:${FLUX_SOURCE_CONTROLLER}" "fluxcd/source-controller:${FLUX_SOURCE_CONTROLLER}"
import "ghcr.io/fluxcd/kustomize-controller:${FLUX_KUSTOMIZE_CONTROLLER}" "fluxcd/kustomize-controller:${FLUX_KUSTOMIZE_CONTROLLER}"
import "ghcr.io/fluxcd/helm-controller:${FLUX_HELM_CONTROLLER}" "fluxcd/helm-controller:${FLUX_HELM_CONTROLLER}"

# Envoy Gateway (chart, controller, proxy)
import "docker.io/envoyproxy/gateway-helm:${ENVOY_GATEWAY_VERSION}" "envoyproxy/gateway-helm:${ENVOY_GATEWAY_VERSION}"
import "docker.io/envoyproxy/gateway:${ENVOY_GATEWAY_VERSION}" "envoyproxy/gateway:${ENVOY_GATEWAY_VERSION}"
import "docker.io/envoyproxy/envoy:${ENVOY_PROXY_TAG}" "envoyproxy/envoy:${ENVOY_PROXY_TAG}"

# cert-manager (chart and all five component images)
import "quay.io/jetstack/charts/cert-manager:${CERT_MANAGER_VERSION}" "jetstack/charts/cert-manager:${CERT_MANAGER_VERSION}"
for c in controller webhook cainjector acmesolver startupapicheck; do
  import "quay.io/jetstack/cert-manager-${c}:${CERT_MANAGER_VERSION}" "jetstack/cert-manager-${c}:${CERT_MANAGER_VERSION}"
done

echo "Done. az acr repository list --name $ACR_NAME -o table"
