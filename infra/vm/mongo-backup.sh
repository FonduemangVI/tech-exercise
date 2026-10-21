#!/usr/bin/env bash
# R12: daily dump of MongoDB to the backups container (W6: that container
# is public, intentionally). The admin connection string is read from Key
# Vault on each run and passed to mongodump through a file descriptor, so
# it is never written to disk or shown in the process list.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=kv.sh
. /usr/local/lib/kv.sh

ts="$(date -u +%Y%m%dT%H%M%SZ)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
archive="${workdir}/db-${ts}.archive.gz"

# Fetched into a variable first: a failure inside <(...) would be hidden
# and mongodump would run with an empty connection string.
uri="$(kv_get mongo-admin-uri)"
mongodump --quiet --gzip --archive="$archive" \
  --config=<(printf 'uri: "%s"\n' "$uri")
unset uri

# Retries cover the Storage role assignment still propagating on first boot
for attempt in 1 2 3 4 5; do
  if blob_put "$archive" "db-${ts}.archive.gz"; then
    echo "[mongo-backup] uploaded db-${ts}.archive.gz"
    exit 0
  fi
  echo "[mongo-backup] upload attempt ${attempt} failed, retrying in 60s"
  sleep 60
done
echo "[mongo-backup] upload failed"
exit 1
