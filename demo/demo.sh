#!/usr/bin/env bash
# Presentation demo. Shows each command, runs it when Enter is pressed.
# No live typing: every command the panel sees is in this file.
#
#   demo/demo.sh check      pre-flight, run before the call (no pauses)
#   demo/demo.sh 1          Demo 1: it is built and it works (about 10 min)
#   demo/demo.sh 2          Demo 2: weaknesses, then the control for each (about 8 min)
#   demo/demo.sh 1 --list   print the steps without running anything
#
# Needs: logged in to az, gh and kubectl (scripts/bootstrap-flux.sh sets up
# the kubeconfig), infra/ initialised locally for its outputs (see
# docs/runbook.md, step 3), and the SSH key ~/.ssh/wiz-exercise.
#
# DRAFT: written before the lab existed. Steps marked "lab check" have not
# been run against the live environment yet.
#
# Nothing here prints a secret value. Secrets are shown by name or key only,
# because the screen is shared.

set -euo pipefail

REPO="${REPO:-FonduemangVI/tech-exercise}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/wiz-exercise}"
LIST_ONLY=false

# ---------- output helpers ----------

if [[ -t 1 ]]; then
  BOLD=$'\e[1m' DIM=$'\e[2m' CYAN=$'\e[36m' GREEN=$'\e[32m' RED=$'\e[31m' RESET=$'\e[0m'
else
  BOLD='' DIM='' CYAN='' GREEN='' RED='' RESET=''
fi

# Section heading
title() { printf '\n%s== %s ==%s\n' "$BOLD" "$*" "$RESET"; }

# What to say or show outside the terminal (browser tab, slide). Waits for
# Enter so the pace stays mine.
say() {
  printf '\n%s> %s%s\n' "$DIM" "$*" "$RESET"
  $LIST_ONLY || read -r -s
}

# Shows the command, waits for Enter, runs it. A failing command does not
# stop the demo: the error stays on screen and the next step still works.
step() {
  printf '\n%s$ %s%s' "$CYAN" "$*" "$RESET"
  if $LIST_ONLY; then
    printf '\n'
    return 0
  fi
  read -r -s
  printf '\n'
  eval "$*" || printf '%s(exit %s)%s\n' "$RED" "$?" "$RESET"
}

# ---------- environment ----------

# Names come from the repo variables and the Terraform outputs, never typed.
load_env() {
  $LIST_ONLY && return 0
  var() { gh variable get "$1" --repo "$REPO"; }
  out() { terraform -chdir=infra output -raw "$1"; }

  APP_HOSTNAME="$(var APP_HOSTNAME)"
  ACR_LOGIN_SERVER="$(var ACR_LOGIN_SERVER)"
  RG="$(out resource_group_name)"
  MONGO_IP="$(out mongo_public_ip)"
  BACKUP_LIST_URL="$(out backup_list_url)"
  LAW_ID="$(out log_analytics_workspace_id)"
}

# load_env for the pre-flight: reports instead of exiting on a missing value
try_load_env() {
  load_env 2>/dev/null || return 1
  [[ -n "$APP_HOSTNAME" && -n "$ACR_LOGIN_SERVER" && -n "$RG" && -n "$MONGO_IP" && -n "$BACKUP_LIST_URL" && -n "$LAW_ID" ]]
}

# ---------- helpers for steps that need more than one line ----------

# Every image running in the cluster, one per line
images() {
  kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' |
    sort -u
}

# Env vars of the tasky container and where they come from (names only)
env_sources() {
  kubectl -n tasky get deploy tasky -o json | jq -r '
    .spec.template.spec.containers[0].env[]
    | if .valueFrom then "\(.name)  <-  secret \(.valueFrom.secretKeyRef.name)/\(.valueFrom.secretKeyRef.key)"
      else "\(.name)=\(.value)" end'
}

# R20: the todos are in MongoDB. SSH in (W4 makes this possible from
# anywhere), read the admin URI from Key Vault with the VM's identity, and
# query. The URI goes through the environment, never the command line, and
# is not printed. Lab check: the kv.sh path and that mongosh's connect()
# accepts the URI as given.
mongo_todos() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "azureuser@$MONGO_IP" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
. /usr/local/lib/kv.sh
MONGO_URI="$(kv_get mongo-admin-uri)" mongosh --quiet --nodb --eval '
  const db = connect(process.env.MONGO_URI).getSiblingDB("go-mongodb");
  print("todos: " + db.todos.countDocuments());
  db.todos.find({}, { _id: 0, name: 1, status: 1 }).sort({ _id: -1 }).limit(3).forEach(printjson);
'
REMOTE
}

# W6: list the backups with no credentials at all
backup_list() {
  curl -fsS "$BACKUP_LIST_URL" | grep -o '<Name>[^<]*</Name>' | sed -e 's/<[^>]*>//g'
}

# W3: what the VM's managed identity can do
vm_roles() {
  local principal
  principal="$(az vm list -g "$RG" --query '[0].identity.principalId' -o tsv)"
  az role assignment list --assignee "$principal" --all \
    --query '[].{role:roleDefinitionName, scope:scope}' -o table
}

# R26 audit: who created role assignments (W3 included). Lab check:
# az monitor log-analytics query output; fallback is the Logs tab.
audit_role_assignments() {
  local workspace
  workspace="$(az monitor log-analytics workspace show --ids "$LAW_ID" --query customerId -o tsv)"
  az monitor log-analytics query -w "$workspace" -o table --analytics-query '
    AzureActivity
    | where OperationNameValue =~ "Microsoft.Authorization/roleAssignments/write"
    | where ActivityStatusValue =~ "Success"
    | project TimeGenerated, Caller, Scope = tostring(Properties_d.entity)
    | order by TimeGenerated desc
    | take 10'
}

# R28 detective: the anonymous reads from backup_list() in Demo 1
anonymous_reads() {
  local workspace
  workspace="$(az monitor log-analytics workspace show --ids "$LAW_ID" --query customerId -o tsv)"
  az monitor log-analytics query -w "$workspace" -o table --analytics-query '
    StorageBlobLogs
    | where AuthenticationType == "Anonymous"
    | where OperationName in ("GetBlob", "ListBlobs", "GetBlobProperties")
    | where Uri has "/backups"
    | project TimeGenerated, OperationName, CallerIpAddress
    | order by TimeGenerated desc
    | take 10'
}

# ---------- pre-flight ----------

check() {
  local ok=true
  pass() { printf '%sOK%s    %s\n' "$GREEN" "$RESET" "$1"; }
  fail() { printf '%sFAIL%s  %s\n' "$RED" "$RESET" "$1"; ok=false; }

  if az account show -o none 2>/dev/null; then pass "Azure CLI logged in"; else fail "az login"; fi
  if gh auth status >/dev/null 2>&1; then pass "gh logged in"; else fail "gh auth login"; fi
  if ! try_load_env; then
    fail "repo variables or Terraform outputs missing (runbook step 3)"
    exit 1
  fi
  pass "repo variables and Terraform outputs"
  # Fails when my public IP is no longer in the authorised range
  if ! kubectl get --raw /readyz >/dev/null 2>&1; then
    fail "API server: has my IP changed? (runbook: day to day)"
    exit 1
  fi
  pass "API server reachable"
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' "https://$APP_HOSTNAME/")" == 200 ]]; then
    pass "app answers on https://$APP_HOSTNAME"
  else
    fail "app on https://$APP_HOSTNAME"
  fi
  if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "azureuser@$MONGO_IP" true 2>/dev/null; then
    pass "SSH to the Mongo VM"
  else
    fail "SSH to $MONGO_IP"
  fi
  # Left behind if a rehearsal ran the policy test while still in Audit
  kubectl delete pod policy-test -n default --ignore-not-found >/dev/null
  if [[ "$(images | grep -cv "^${ACR_LOGIN_SERVER}/" || true)" -eq 0 ]]; then
    pass "every running image is from ACR"
  else
    printf '%sNOTE%s  images outside ACR (fine only in excluded namespaces):\n' "$DIM" "$RESET"
    images | grep -v "^${ACR_LOGIN_SERVER}/" | sed 's/^/        /'
  fi

  if $ok; then
    printf '\n%sReady.%s\n' "$GREEN" "$RESET"
  else
    printf '\n%sFix the FAIL lines before the call.%s\n' "$RED" "$RESET"
    exit 1
  fi
}

# ---------- Demo 1: it is built and it works ----------

demo1() {
  title "Demo 1: the environment"

  # R14: no node has a public IP
  step kubectl get nodes -o wide

  # R2: Flux installs the platform from Git
  step kubectl get fluxinstance -n flux-system
  step kubectl get kustomizations,helmreleases -A

  # R5, R18: Gateway API ingress behind the Azure load balancer, with TLS
  step kubectl -n network get gateway,certificate,svc
  step kubectl get httproute -A
  # shellcheck disable=SC2016 # shown as typed, expanded by eval in step
  step 'curl -sI "http://$APP_HOSTNAME/" | head -n 3   # port 80 only redirects to HTTPS'

  say "Browser: open the app, sign up, add a todo"

  # R16: the file is in the running container
  step kubectl exec -n tasky deploy/tasky -- cat /app/wizexercise.txt

  # R15: the connection string reaches the app as an env var, from a
  # Secret synced from Key Vault (names only, no values)
  step 'env_sources   # deployment env vars: names and secret keys, no values'

  # R20: the todo just added is in MongoDB on the VM (lab check)
  step 'mongo_todos   # SSH to the VM, admin URI from Key Vault, count the todos'

  # ACR is the only image source
  step 'images   # every image running in the cluster'

  # R12, W6: dated backups, listed without any credentials. This also
  # triggers the alert shown in Demo 2.
  step 'backup_list   # anonymous listing of the backups container, no credentials'
}

# ---------- Demo 2: weaknesses, and the control for each ----------

demo2() {
  title "Demo 2: weaknesses and controls"

  # W5: the app's service account can do anything in the cluster
  step 'kubectl auth can-i --list --as=system:serviceaccount:tasky:tasky-sa | head -n 5'
  step kubectl auth can-i get secrets --all-namespaces --as=system:serviceaccount:tasky:tasky-sa
  # ...including the Secret holding the Mongo URI (keys only)
  step "kubectl -n tasky get secret tasky-secrets -o jsonpath='{.data}' | jq -r 'keys[]'"

  # W3: the VM identity is Contributor on the whole subscription
  step 'vm_roles   # role assignments of the VM managed identity'

  # Audit (R26): every role assignment is attributable (lab check)
  step 'audit_role_assignments   # Activity Log in Log Analytics: who created role assignments'

  # Preventative (R27): only ACR images may run. Run in "default": tasky's
  # Pod Security "restricted" label would reject this pod first and hide
  # the policy.
  step kubectl run policy-test --image=docker.io/library/nginx -n default --restart=Never

  # Detective (R28): the anonymous listing from Demo 1 (lab check)
  step 'anonymous_reads   # storage logs: the anonymous listing from Demo 1'
  say "Portal: Monitor > Alerts, the W6 alert has fired"

  say "Portal: Defender for Cloud recommendations for the VM, storage and AKS"
}

# ---------- main ----------

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[[ "${2:-}" == "--list" ]] && LIST_ONLY=true
case "${1:-}" in
  check) check ;;
  1) load_env; demo1 ;;
  2) load_env; demo2 ;;
  *) usage ;;
esac
