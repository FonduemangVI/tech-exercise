#!/usr/bin/env bash
# Sets the repository variables app.yml needs, from the infra/ outputs.
# Run once after the first infra apply, from the repository root, with
# infra/ initialised locally (terraform -chdir=infra init -backend-config=backend.hcl).
#
# None of these are secrets: names, a client ID and a hostname.

set -euo pipefail

REPO="${REPO:-FonduemangVI/tech-exercise}"

tf_out() { terraform -chdir=infra output -json | jq -r "$1"; }

ACR_LOGIN_SERVER="$(tf_out '.acr_login_server.value')"
ACR_NAME="${ACR_LOGIN_SERVER%%.*}"
AKS_NAME="$(tf_out '.aks_name.value')"
AKS_RESOURCE_GROUP="$(tf_out '.resource_group_name.value')"
KEY_VAULT_NAME="$(tf_out '.key_vault_name.value')"
TASKY_CLIENT_ID="$(tf_out '.workload_identity_client_ids.value.tasky')"
LOCATION="$(gh variable get AZURE_LOCATION --repo "$REPO")"

# DNS label on the Envoy load balancer IP. Must be unique in the region, so
# it reuses the registry's random suffix.
APP_DNS_LABEL="${APP_DNS_LABEL:-tasky-${ACR_NAME: -5}}"
APP_HOSTNAME="${APP_DNS_LABEL}.${LOCATION}.cloudapp.azure.com"

set_var() {
  echo "  $1=$2"
  gh variable set "$1" --repo "$REPO" --body "$2"
}

echo "Setting app variables on $REPO"
set_var ACR_NAME "$ACR_NAME"
set_var ACR_LOGIN_SERVER "$ACR_LOGIN_SERVER"
set_var AKS_NAME "$AKS_NAME"
set_var AKS_RESOURCE_GROUP "$AKS_RESOURCE_GROUP"
set_var KEY_VAULT_NAME "$KEY_VAULT_NAME"
set_var TASKY_CLIENT_ID "$TASKY_CLIENT_ID"
set_var APP_DNS_LABEL "$APP_DNS_LABEL"
set_var APP_HOSTNAME "$APP_HOSTNAME"
