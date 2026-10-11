#!/bin/bash
# Root-level entrypoint: fix volume ownership, bootstrap as `frappe`, start supervisord.
set -euo pipefail

BENCH_DIR=/home/frappe/frappe-bench
SITES_DIR="${BENCH_DIR}/sites"
FRAPPE_UID=1000
FRAPPE_GID=0

log() { echo "[railway-entrypoint] $*"; }

# --- Defaults for the supervisor template -----------------------------------
export PORT="${PORT:-8080}"
export SITE_NAME="${SITE_NAME:-erpnext.local}"
export WORKER_SHORT_PROCS="${WORKER_SHORT_PROCS:-1}"
export WORKER_LONG_PROCS="${WORKER_LONG_PROCS:-1}"
export CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-50m}"
export PROXY_READ_TIMEOUT="${PROXY_READ_TIMEOUT:-120}"

for n in WORKER_SHORT_PROCS WORKER_LONG_PROCS; do
  if ! [[ "${!n}" =~ ^[1-9][0-9]*$ ]]; then
    log "ERROR: ${n} must be a positive integer (got '${!n}')"
    exit 1
  fi
done

# --- Volume ownership ---------------------------------------------------------
# Railway mounts volumes owned by root; the official image runs Frappe as uid 1000.
mkdir -p "${SITES_DIR}"
rm -rf "${SITES_DIR}/lost+found"
if [ "$(stat -c %u "${SITES_DIR}")" != "${FRAPPE_UID}" ]; then
  log "Fixing ownership of ${SITES_DIR} (first boot on a new volume)"
  chown -R "${FRAPPE_UID}:${FRAPPE_GID}" "${SITES_DIR}"
fi
chmod g+rwx "${SITES_DIR}"

# --- Configure bench and create the site (runs as frappe) ---------------------
runuser -u frappe -- env HOME=/home/frappe /usr/local/bin/railway-bootstrap.sh

# --- Start all processes --------------------------------------------------------
envsubst '${PORT} ${SITE_NAME} ${WORKER_SHORT_PROCS} ${WORKER_LONG_PROCS} ${CLIENT_MAX_BODY_SIZE} ${PROXY_READ_TIMEOUT}' \
  < /templates/supervisord.conf.template > /etc/supervisor/railway-supervisord.conf

log "Starting supervisord (web, socket.io, ${WORKER_SHORT_PROCS} short + ${WORKER_LONG_PROCS} long worker(s), scheduler, nginx on :${PORT})"
exec /usr/bin/supervisord -n -c /etc/supervisor/railway-supervisord.conf
