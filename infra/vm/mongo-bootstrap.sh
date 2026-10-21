#!/usr/bin/env bash
# First boot only (cloud-init runcmd). Installs MongoDB, creates the admin
# and app users, stores the connection strings in Key Vault, then turns
# on authentication and listens on the private IP.
#
# Passwords are generated here, on the host that uses them. If the secrets
# already exist (the VM was rebuilt), the same passwords are reused so
# tasky's connection string stays valid.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=kv.sh
. /usr/local/lib/kv.sh

log() { echo "[mongo-bootstrap] $*"; }

# $1 = host. Waits up to 2 minutes for mongod to answer a ping (allowed
# without authentication). Fails if it never does.
wait_for_mongod() {
  local host="$1"
  for _ in $(seq 1 60); do
    if mongosh --quiet --host "$host" --eval 'db.runCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  log "mongod not answering on ${host} after 2 minutes"
  return 1
}

# --- 1. MongoDB (W2: version past end of life, intentional) ---------------
keyring="/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg"
curl -fsSL "https://pgp.mongodb.com/server-${MONGO_VERSION}.asc" | gpg --batch --yes --dearmor -o "$keyring"
echo "deb [ arch=amd64,arm64 signed-by=${keyring} ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/${MONGO_VERSION} multiverse" \
  >"/etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q mongodb-org
systemctl enable --now mongod

# Package default: auth off, localhost only. Users are created in this state.
wait_for_mongod 127.0.0.1

# --- 2. Wait for Key Vault (role assignments take a few minutes) ----------
code=000
for _ in $(seq 1 90); do
  code="$(kv_status mongo-admin-uri || true)"
  [[ "$code" == 200 || "$code" == 404 ]] && break
  log "Key Vault not ready (HTTP ${code}), retrying in 20s"
  sleep 20
done
if [[ "$code" != 200 && "$code" != 404 ]]; then
  log "no Key Vault access after 30 minutes, giving up"
  exit 1
fi

# --- 3. Reuse existing passwords, or generate new ones --------------------
password_from_uri() { sed -E 's#^mongodb://[^:]+:([^@]+)@.*#\1#'; }

declare -A new_secret=()

if [[ "$(kv_status mongo-admin-uri)" == 200 ]]; then
  ADMIN_PW="$(kv_get mongo-admin-uri | password_from_uri)"
else
  ADMIN_PW="$(openssl rand -hex 24)"
  new_secret[mongo-admin-uri]=1
fi

if [[ "$(kv_status mongo-app-uri)" == 200 ]]; then
  APP_PW="$(kv_get mongo-app-uri | password_from_uri)"
else
  APP_PW="$(openssl rand -hex 24)"
  new_secret[mongo-app-uri]=1
fi

if [[ "$(kv_status tasky-jwt-secret)" != 200 ]]; then
  new_secret[tasky-jwt-secret]=1
fi

# --- 4. Users (auth still off, localhost only) ----------------------------
# Passwords reach mongosh through the environment, not the command line.
ADMIN_PW="$ADMIN_PW" APP_PW="$APP_PW" mongosh --quiet admin --eval '
  if (!db.getUser("admin")) {
    db.createUser({ user: "admin", pwd: process.env.ADMIN_PW, roles: ["root"] });
  }
  const app = db.getSiblingDB("go-mongodb");
  if (!app.getUser("tasky")) {
    app.createUser({ user: "tasky", pwd: process.env.APP_PW,
                     roles: [{ role: "readWrite", db: "go-mongodb" }] });
  }'
log "users present: admin (root), tasky (readWrite on go-mongodb)"

# --- 5. Store the connection strings --------------------------------------
if [[ -n "${new_secret[mongo-admin-uri]:-}" ]]; then
  printf 'mongodb://admin:%s@127.0.0.1:27017/?authSource=admin' "$ADMIN_PW" | kv_set mongo-admin-uri
  log "wrote mongo-admin-uri"
fi
if [[ -n "${new_secret[mongo-app-uri]:-}" ]]; then
  printf 'mongodb://tasky:%s@%s:27017/go-mongodb?authSource=go-mongodb' "$APP_PW" "$MONGO_PRIVATE_IP" | kv_set mongo-app-uri
  log "wrote mongo-app-uri"
fi
if [[ -n "${new_secret[tasky-jwt-secret]:-}" ]]; then
  openssl rand -hex 32 | tr -d '\n' | kv_set tasky-jwt-secret
  log "wrote tasky-jwt-secret"
fi
unset ADMIN_PW APP_PW

# --- 6. Auth on; listen on localhost and the private IP only --------------
# The NSG limits 27017 to the AKS node subnet (R11).
cat >/etc/mongod.conf <<CONF
storage:
  dbPath: /var/lib/mongodb
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 127.0.0.1,${MONGO_PRIVATE_IP}
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
security:
  authorization: enabled
CONF
systemctl restart mongod
log "authentication enabled, listening on 127.0.0.1 and ${MONGO_PRIVATE_IP}"

# Pinging the private IP also proves the new bindIp took effect.
wait_for_mongod "$MONGO_PRIVATE_IP"

# --- 7. First backup, so a blob exists straight away ----------------------
# A failed first backup does not fail the bootstrap: MongoDB, the users and
# the secrets are already in place, and cron runs again at 02:00 UTC.
/usr/local/sbin/mongo-backup.sh || log "first backup failed; cron retries at 02:00 UTC"
