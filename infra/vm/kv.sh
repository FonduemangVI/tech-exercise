# shellcheck shell=bash
# Helpers for Key Vault and Blob Storage using the VM's managed identity.
# Plain REST calls with an IMDS token, no Azure CLI.
#
# - Tokens reach curl through a file descriptor (-H @<(...)) and secret
#   values through stdin, so neither shows up in the process list.
# - Needs bash (process substitution) and curl 7.55+ (-H @file). Ubuntu
#   20.04 ships curl 7.68: no --fail-with-body (7.76) or --retry-all-errors
#   (7.71), hence the manual status handling in az_request.
# - No token caching: IMDS allows about 5 requests per second, and these
#   scripts make a handful per run.

# shellcheck source=/dev/null
. "${MONGO_VM_ENV:-/etc/mongo-vm.env}"

KV_API_VERSION="7.4"
BLOB_API_VERSION="2023-11-03"
KV_RESOURCE="https%3A%2F%2Fvault.azure.net"
STORAGE_RESOURCE="https%3A%2F%2Fstorage.azure.com%2F"
IMDS_TOKEN_URL="${IMDS_TOKEN_URL:-http://169.254.169.254/metadata/identity/oauth2/token}"

# Fail fast on a dead connection. Data-plane calls are retried in bash
# (az_request), not with curl --retry: without --fail, curl writes the body
# of every attempt to stdout, so a retried 503 would corrupt the output.
CURL_OPTS=(--silent --show-error --connect-timeout 10)

# $1 = resource, URL-encoded. Prints an access token, or fails.
# --fail means failed attempts write nothing, so curl's --retry is safe here.
imds_token() {
  local resp
  resp="$(curl "${CURL_OPTS[@]}" --fail --retry 3 --retry-delay 2 --max-time 30 \
    -H "Metadata: true" "${IMDS_TOKEN_URL}?api-version=2018-02-01&resource=$1")" || {
    echo "imds_token: IMDS request failed" >&2
    return 1
  }
  printf '%s' "$resp" | jq -er '.access_token // empty' || {
    echo "imds_token: no access_token in the IMDS response" >&2
    return 1
  }
}

# az_request <resource> <method> <url> [extra curl args...]
# Prints the response body on 2xx. Retries transient failures (no
# connection, 408, 429, 5xx) up to 4 attempts; anything else fails at once
# with the status and error body on stderr. Key Vault and Storage error
# bodies describe the failure; they never contain secret values.
#   AZ_BODY      request body, sent on stdin and re-sent on each attempt
#   AZ_MAX_TIME  per-attempt limit in seconds (default 30)
az_request() {
  local resource="$1" method="$2" url="$3"
  shift 3
  local token out status body attempt

  # Fetched here, not inside <(...): a failure in a process substitution
  # never reaches the caller, and curl would send an empty bearer token.
  token="$(imds_token "$resource")" || return 1

  for attempt in 1 2 3 4; do
    if [[ -n "${AZ_BODY+set}" ]]; then
      out="$(printf '%s' "$AZ_BODY" |
        curl "${CURL_OPTS[@]}" --max-time "${AZ_MAX_TIME:-30}" -X "$method" \
          -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "$token") \
          --data-binary @- "$@" "$url")" || out=$'\n000'
    else
      out="$(curl "${CURL_OPTS[@]}" --max-time "${AZ_MAX_TIME:-30}" -X "$method" \
        -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "$token") \
        "$@" "$url")" || out=$'\n000'
    fi
    status="${out##*$'\n'}"
    body="${out%$'\n'*}"

    case "$status" in
      2??)
        printf '%s' "$body"
        return 0
        ;;
      000 | 408 | 429 | 5??)
        echo "az_request: ${method} ${url%%\?*}: HTTP ${status} on attempt ${attempt}" >&2
        sleep $((attempt * 3))
        ;;
      *) break ;;
    esac
  done
  echo "az_request: ${method} ${url%%\?*} failed with HTTP ${status}: ${body}" >&2
  return 1
}

# $1 = secret name. Prints the HTTP status only: 200 exists, 404 absent,
# 401/403 no access yet (role still propagating, or firewall), 000 no
# connection or no token. -o /dev/null, so curl's --retry is safe here.
kv_status() {
  local token
  token="$(imds_token "$KV_RESOURCE")" || {
    echo 000
    return 0
  }
  curl "${CURL_OPTS[@]}" --retry 3 --retry-delay 2 --max-time 30 -o /dev/null -w '%{http_code}' \
    -H @<(printf 'Authorization: Bearer %s' "$token") \
    "${KV_URI%/}/secrets/$1?api-version=${KV_API_VERSION}" || true
}

# $1 = secret name. Prints the value; fails if the secret has no value.
kv_get() {
  local body
  body="$(az_request "$KV_RESOURCE" GET "${KV_URI%/}/secrets/$1?api-version=${KV_API_VERSION}")" || return 1
  printf '%s' "$body" | jq -er '.value // empty'
}

# $1 = secret name. Reads the value from stdin. The payload is held in a
# variable and piped with printf (a bash builtin), so it is never in the
# process list, and az_request can re-send it on retry.
kv_set() {
  local AZ_BODY
  AZ_BODY="$(jq -Rs '{value: ., contentType: "text/plain"}')" || return 1
  az_request "$KV_RESOURCE" PUT "${KV_URI%/}/secrets/$1?api-version=${KV_API_VERSION}" \
    -H "Content-Type: application/json" >/dev/null
}

# $1 = local file, $2 = blob name in the backup container.
blob_put() {
  AZ_MAX_TIME=600 az_request "$STORAGE_RESOURCE" PUT \
    "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${BACKUP_CONTAINER}/$2" \
    -H "x-ms-version: ${BLOB_API_VERSION}" -H "x-ms-blob-type: BlockBlob" \
    --upload-file "$1" >/dev/null
}
