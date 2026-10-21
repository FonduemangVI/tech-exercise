#!/usr/bin/env bash
# Creates the GitHub environments and repository variables that the
# pipelines need, using the outputs of infra/bootstrap.
#
# Run from the repository root after `terraform apply` in infra/bootstrap.
# Requires: terraform, jq, gh (authenticated with repo admin rights).
#
# Nothing written here is a secret: client IDs, tenant ID, subscription ID
# and storage names are identifiers. Access is controlled by the federated
# credential subjects and Azure RBAC, not by keeping these values hidden.

set -euo pipefail

REPO="${REPO:-FonduemangVI/tech-exercise}"
TF_DIR="infra/bootstrap"

tf_out() {
  terraform -chdir="$TF_DIR" output -json | jq -r "$1"
}

echo "Reading bootstrap outputs from $TF_DIR"
TENANT_ID="$(tf_out '.tenant_id.value')"
SUBSCRIPTION_ID="$(tf_out '.subscription_id.value')"
CLIENT_ID_INFRA="$(tf_out '.github_client_ids.value.infra')"
CLIENT_ID_APP="$(tf_out '.github_client_ids.value.app')"
CLIENT_ID_PR="$(tf_out '.github_client_ids.value.pr')"
TFSTATE_RG="$(tf_out '.tfstate.value.resource_group_name')"
TFSTATE_SA="$(tf_out '.tfstate.value.storage_account_name')"
TFSTATE_CONTAINER="$(tf_out '.tfstate.value.container_name')"
ENV_INFRA="$(tf_out '.github_environments.value.infra')"
ENV_APP="$(tf_out '.github_environments.value.app')"

MY_USER_ID="$(gh api user --jq '.id')"

# Creates an environment that only the main branch can deploy to.
# With require_reviewer=yes, the job waits for my approval before it runs.
create_environment() {
  local env="$1" require_reviewer="$2" body

  if [[ "$require_reviewer" == "yes" ]]; then
    body="$(jq -n --argjson id "$MY_USER_ID" '{
      reviewers: [{type: "User", id: $id}],
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
    }')"
  else
    body="$(jq -n '{
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
    }')"
  fi

  echo "Creating environment $env (reviewer required: $require_reviewer)"
  gh api -X PUT "repos/$REPO/environments/$env" --input - <<<"$body" >/dev/null

  # Fails harmlessly if the policy already exists
  gh api -X POST "repos/$REPO/environments/$env/deployment-branch-policies" \
    -f name=main -f type=branch >/dev/null 2>&1 \
    || echo "  branch policy for main already present on $env"
}

create_environment "$ENV_INFRA" yes
create_environment "$ENV_APP" no

echo "Setting repository variables"
gh variable set AZURE_TENANT_ID         --repo "$REPO" --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID   --repo "$REPO" --body "$SUBSCRIPTION_ID"
gh variable set AZURE_CLIENT_ID_INFRA   --repo "$REPO" --body "$CLIENT_ID_INFRA"
gh variable set AZURE_CLIENT_ID_APP     --repo "$REPO" --body "$CLIENT_ID_APP"
gh variable set AZURE_CLIENT_ID_PR      --repo "$REPO" --body "$CLIENT_ID_PR"
gh variable set TFSTATE_RESOURCE_GROUP  --repo "$REPO" --body "$TFSTATE_RG"
gh variable set TFSTATE_STORAGE_ACCOUNT --repo "$REPO" --body "$TFSTATE_SA"
gh variable set TFSTATE_CONTAINER       --repo "$REPO" --body "$TFSTATE_CONTAINER"

echo "Done. Check: gh variable list --repo $REPO"
