#!/bin/bash
# Runs as the `frappe` user before supervisord starts.
# 1. links the image's built assets into the sites volume
# 2. writes common_site_config.json from Railway variables (every boot)
# 3. creates the site with ERPNext on first boot
# 4. runs `bench migrate` once after an image upgrade
set -euo pipefail
umask 0002

cd /home/frappe/frappe-bench

log() { echo "[railway-bootstrap] $*"; }
fail() { echo "[railway-bootstrap] ERROR: $*" >&2; exit 1; }

: "${SITE_NAME:?SITE_NAME is required}"
: "${DB_HOST:?DB_HOST is required (MariaDB private domain)}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD is required}"
: "${REDIS_CACHE_URL:?REDIS_CACHE_URL is required}"
: "${REDIS_QUEUE_URL:?REDIS_QUEUE_URL is required}"
DB_PORT="${DB_PORT:-3306}"
AUTO_MIGRATE="${AUTO_MIGRATE:-true}"
IMAGE_VERSION="${ERPNEXT_IMAGE_VERSION:-unknown}"

STARTED_MARKER="sites/.railway-install-started-${SITE_NAME}"
DONE_MARKER="sites/.railway-install-complete-${SITE_NAME}"
VERSION_FILE="sites/.railway-erpnext-version"

hostport() {
  # redis://user:pass@host:port/db -> host:port
  local rest="${1#*://}"
  rest="${rest##*@}"
  echo "${rest%%/*}"
}

# --- 1. Assets: the image keeps compiled assets outside the volume ------------
rm -rf sites/assets
ln -s /home/frappe/frappe-bench/assets sites/assets
ls -1 apps > sites/apps.txt
cp /home/frappe/frappe-bench/.image-apps.json sites/apps.json

# --- 2. Bench-wide configuration (re-applied every boot) ------------------------
[ -f sites/common_site_config.json ] || echo '{}' > sites/common_site_config.json
bench set-config -g db_host "${DB_HOST}"
bench set-config -gp db_port "${DB_PORT}"
bench set-config -g redis_cache "${REDIS_CACHE_URL}"
bench set-config -g redis_queue "${REDIS_QUEUE_URL}"
bench set-config -g redis_socketio "${REDIS_QUEUE_URL}"
bench set-config -gp socketio_port 9000

log "Waiting for MariaDB and Redis"
wait-for-it -t 180 "${DB_HOST}:${DB_PORT}" || fail "MariaDB not reachable at ${DB_HOST}:${DB_PORT}"
wait-for-it -t 120 "$(hostport "${REDIS_CACHE_URL}")" || fail "redis-cache not reachable"
wait-for-it -t 120 "$(hostport "${REDIS_QUEUE_URL}")" || fail "redis-queue not reachable"

# --- 3. First boot: create the site -----------------------------------------------
# A previous attempt that crashed half-way leaves the "started" marker without the
# "complete" marker: drop that partial site and try again. Sites this script did not
# create (e.g. restored from a backup) never carry the "started" marker and are left alone.
if [ -f "${STARTED_MARKER}" ] && [ ! -f "${DONE_MARKER}" ]; then
  log "Previous site creation for ${SITE_NAME} did not finish; dropping the partial site and retrying"
  bench drop-site "${SITE_NAME}" --force --no-backup \
    --db-root-username root --db-root-password "${DB_ROOT_PASSWORD}" || true
  rm -rf "sites/${SITE_NAME}"
fi

if [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
  : "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required to create the site}"
  log "Creating site ${SITE_NAME} with ERPNext ${IMAGE_VERSION} (takes several minutes on first boot)"
  touch "${STARTED_MARKER}"
  bench new-site "${SITE_NAME}" \
    --mariadb-user-host-login-scope='%' \
    --db-root-username root \
    --db-root-password "${DB_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --install-app erpnext \
    --set-default
  bench --site "${SITE_NAME}" enable-scheduler
  echo "${IMAGE_VERSION}" > "${VERSION_FILE}"
  touch "${DONE_MARKER}"
  log "Site ${SITE_NAME} created"
fi

# Links in e-mails and background jobs use host_name; keep it in sync with the domain.
if [ -n "${PUBLIC_URL:-}" ]; then
  bench --site "${SITE_NAME}" set-config host_name "${PUBLIC_URL}"
fi

# --- 4. Upgrades: migrate once per image version ----------------------------------
current="$(cat "${VERSION_FILE}" 2>/dev/null || echo none)"
if [ "${current}" != "${IMAGE_VERSION}" ]; then
  if [ "${AUTO_MIGRATE}" = "true" ]; then
    log "Image version changed (${current} -> ${IMAGE_VERSION}); running bench migrate"
    bench --site all migrate
    echo "${IMAGE_VERSION}" > "${VERSION_FILE}"
  else
    log "Image version changed (${current} -> ${IMAGE_VERSION}) but AUTO_MIGRATE=false; run 'bench --site all migrate' manually"
  fi
fi

log "Bootstrap finished"
