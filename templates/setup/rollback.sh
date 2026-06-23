#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Roll back to a previous image tag
#
# Usage (run on the production server):
#   bash rollback.sh sha-abc1234
#   bash rollback.sh latest
#   bash rollback.sh          ← lists available tags and prompts for one
#
# Or via SSH from your local machine:
#   ssh deploy@<server> 'cd {{DEPLOY_PATH}} && bash .github/setup/rollback.sh sha-abc1234'
# =============================================================================

set -euo pipefail

DEPLOY_PATH="{{DEPLOY_PATH}}"
APP_IMAGE="ghcr.io/{{GITHUB_REPO_OWNER}}/{{APP_NAME_SLUG}}"
HAS_HORIZON="{{HAS_HORIZON}}"
DB_SERVICE="{{DB_SERVICE_NAME}}"
COMPOSE="docker compose -f ${DEPLOY_PATH}/docker-compose.prod.yaml"

log()  { echo "[rollback] $*"; }
die()  { echo "[rollback][ERROR] $*" >&2; exit 1; }

cd "${DEPLOY_PATH}"

# ---------------------------------------------------------------
# 1. Determine target image tag
# ---------------------------------------------------------------
TARGET_TAG="${1:-}"

if [ -z "${TARGET_TAG}" ]; then
  log "Available app image tags on this server:"
  docker images "${APP_IMAGE}" --format "{{.Tag}}\t{{.CreatedSince}}\t{{.Size}}" \
    | grep -v "buildcache\|nginx" \
    | sort -r \
    | head -15
  echo ""
  read -rp "Enter tag to roll back to (e.g. sha-abc1234): " TARGET_TAG
fi

[ -n "${TARGET_TAG}" ] || die "No tag specified."
log "Rolling back to: ${TARGET_TAG}"

# ---------------------------------------------------------------
# 2. Confirm the image exists locally (or pull it)
# ---------------------------------------------------------------
if ! docker images "${APP_IMAGE}:${TARGET_TAG}" --format "{{.Tag}}" | grep -q "${TARGET_TAG}"; then
  log "Image not found locally — pulling from GHCR..."
  GHCR_TOKEN=$(grep '^GHCR_PULL_TOKEN=' .env | cut -d= -f2- | tr -d '"')
  [ -n "${GHCR_TOKEN}" ] || die "GHCR_PULL_TOKEN not found in .env"
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "{{GITHUB_REPO_OWNER}}" --password-stdin
fi

# ---------------------------------------------------------------
# 3. Pin the rollback tag
# ---------------------------------------------------------------
echo "APP_IMAGE_TAG=${TARGET_TAG}" > .image-tag.env
COMPOSE_WITH_TAG="${COMPOSE} --env-file .image-tag.env"

# ---------------------------------------------------------------
# 4. Pull target images (nginx too — assets are baked in)
# ---------------------------------------------------------------
PULL_SVCS="app nginx scheduler"
if [ "${HAS_HORIZON}" = "true" ]; then PULL_SVCS="${PULL_SVCS} horizon"; fi
${COMPOSE_WITH_TAG} pull ${PULL_SVCS}

# ---------------------------------------------------------------
# 5. Ensure DB is healthy before any artisan commands
# ---------------------------------------------------------------
${COMPOSE_WITH_TAG} up -d --no-deps --wait "${DB_SERVICE}" redis

# ---------------------------------------------------------------
# 6. Rolling restart of app container
# ---------------------------------------------------------------
${COMPOSE_WITH_TAG} up -d --no-deps --wait app

# ---------------------------------------------------------------
# 7. Rebuild framework caches from the rolled-back code
# ---------------------------------------------------------------
${COMPOSE} exec -T app php artisan config:cache
${COMPOSE} exec -T app php artisan route:cache
${COMPOSE} exec -T app php artisan view:cache
${COMPOSE} exec -T app php artisan event:cache

# ---------------------------------------------------------------
# 8. Graceful Horizon drain + restart (if applicable)
# ---------------------------------------------------------------
if [ "${HAS_HORIZON}" = "true" ]; then
  ${COMPOSE} exec -T horizon php artisan horizon:terminate || true
  log "Waiting for Horizon to drain..."
  for i in $(seq 1 20); do
    STATUS=$(${COMPOSE} exec -T horizon php artisan horizon:status 2>/dev/null || echo "inactive")
    echo "  Status: ${STATUS} (${i}/20)"
    echo "${STATUS}" | grep -qi "inactive\|stopped" && break
    sleep 5
  done
  ${COMPOSE_WITH_TAG} up -d --no-deps horizon scheduler
else
  ${COMPOSE_WITH_TAG} up -d --no-deps scheduler
fi

# ---------------------------------------------------------------
# 9. Swap nginx to the rolled-back image
# ---------------------------------------------------------------
${COMPOSE_WITH_TAG} up -d --no-deps --wait nginx

log "Rollback complete — now running: ${TARGET_TAG}"
log "Verify: curl -si https://{{PROD_DOMAIN}}/up"
