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

# Platform images (Flux Operator, Envoy Gateway, cert-manager) are added
# with the platform change.

echo "Done. az acr repository list --name $ACR_NAME -o table"
