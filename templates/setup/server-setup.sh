#!/usr/bin/env bash
# =============================================================================
# server-setup.sh — One-time bootstrap for {{PROD_DOMAIN}} on {{PROD_SERVER_IP}}
#
# Run once as the deploy user (which should have full sudo):
#   bash server-setup.sh
#
# Prerequisites before running:
#   1. {{DEPLOY_PATH}}/.env   — production env file (created manually from .env.production.example)
#   2. The deploy user's SSH public key must be added to authorized_keys
#   3. DNS for {{PROD_DOMAIN}} must resolve to {{PROD_SERVER_IP}}
# =============================================================================

set -euo pipefail

DEPLOY_DIR="{{DEPLOY_PATH}}"
REPO="git@github.com:{{GITHUB_REPO_OWNER}}/{{APP_NAME_SLUG}}.git"
NGINX_AVAILABLE="/etc/nginx/sites-available/{{PROD_DOMAIN}}"
NGINX_ENABLED="/etc/nginx/sites-enabled/{{PROD_DOMAIN}}"
BACKUP_SCRIPT="/usr/local/bin/db-backup-{{APP_NAME_SLUG}}.sh"

log()  { echo "[setup] $*"; }
warn() { echo "[setup][WARN] $*"; }
die()  { echo "[setup][ERROR] $*" >&2; exit 1; }

# ---------------------------------------------------------------
# 1. Install Docker CE + Compose plugin
# ---------------------------------------------------------------
if command -v docker &>/dev/null; then
  log "Docker already installed: $(docker --version)"
else
  log "Installing Docker CE..."
  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  log "Docker installed: $(docker --version)"
fi

# ---------------------------------------------------------------
# 2. Add deploy user to docker group
# ---------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  log "Running as root — skipping docker group step (root has full Docker access)"
elif groups "$(id -un)" | grep -q docker; then
  log "User already in docker group"
else
  log "Adding user to docker group..."
  sudo usermod -aG docker "$(id -un)"
  warn "Log out and back in (or run 'newgrp docker') for the group to take effect."
fi

# ---------------------------------------------------------------
# 3. Create deploy directory structure
# ---------------------------------------------------------------
log "Creating deploy directory: ${DEPLOY_DIR}"
sudo mkdir -p "${DEPLOY_DIR}/backups"
sudo chown -R "$(id -un):$(id -gn)" "${DEPLOY_DIR}"
chmod 750 "${DEPLOY_DIR}"
chmod 700 "${DEPLOY_DIR}/backups"

# ---------------------------------------------------------------
# 4. Clone the repository
# ---------------------------------------------------------------
if [ -d "${DEPLOY_DIR}/.git" ]; then
  log "Repo already cloned, pulling latest..."
  git -C "${DEPLOY_DIR}" pull --ff-only origin main
else
  log "Cloning repository into ${DEPLOY_DIR}..."
  # Requires the deploy user's SSH key to have read access to the repo.
  # Alternatively use HTTPS with a PAT:
  #   git clone https://<PAT>@github.com/{{GITHUB_REPO_OWNER}}/{{APP_NAME_SLUG}}.git "${DEPLOY_DIR}"
  git clone "${REPO}" "${DEPLOY_DIR}"
fi

# ---------------------------------------------------------------
# 5. Verify .env file exists
# ---------------------------------------------------------------
[ -f "${DEPLOY_DIR}/.env" ] \
  || die ".env not found at ${DEPLOY_DIR}/.env — create it from .env.production.example before running this script"

# ---------------------------------------------------------------
# 6. Authenticate with GitHub Container Registry
# ---------------------------------------------------------------
log "Logging in to ghcr.io..."
GHCR_TOKEN=$(grep '^GHCR_PULL_TOKEN=' "${DEPLOY_DIR}/.env" | cut -d= -f2- | tr -d '"')
[ -n "${GHCR_TOKEN}" ] || die "GHCR_PULL_TOKEN not found in .env — add it first"
echo "${GHCR_TOKEN}" | docker login ghcr.io -u {{GITHUB_REPO_OWNER}} --password-stdin

# ---------------------------------------------------------------
# 7. Pull Docker images and start the stack
# ---------------------------------------------------------------
log "Pulling production images..."
docker compose -f "${DEPLOY_DIR}/docker-compose.prod.yaml" pull

log "Starting production stack..."
docker compose -f "${DEPLOY_DIR}/docker-compose.prod.yaml" up -d

log "Waiting for app container to become healthy (up to 120s)..."
for i in $(seq 1 24); do
  APP_CID=$(docker compose -f "${DEPLOY_DIR}/docker-compose.prod.yaml" ps -q app 2>/dev/null || true)
  if [ -n "${APP_CID}" ]; then
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${APP_CID}" 2>/dev/null || echo "unknown")
    echo "  Health: ${STATUS} (${i}/24)"
    [ "${STATUS}" = "healthy" ] && break
  fi
  if [ "${i}" -eq 24 ]; then
    echo "ERROR: app container did not become healthy in 120s"
    docker compose -f "${DEPLOY_DIR}/docker-compose.prod.yaml" logs app --tail 60
    die "Stack failed to start — review logs above"
  fi
  sleep 5
done

log "Stack is up:"
docker compose -f "${DEPLOY_DIR}/docker-compose.prod.yaml" ps

# ---------------------------------------------------------------
# 8. Install DB backup script
# ---------------------------------------------------------------
log "Installing DB backup script at ${BACKUP_SCRIPT}..."
sudo tee "${BACKUP_SCRIPT}" > /dev/null << 'BACKUP_EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="{{DEPLOY_PATH}}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/db_${TIMESTAMP}.sql.gz"

ENV_FILE="{{DEPLOY_PATH}}/.env"

# MySQL backup (replace with pg_dump for PostgreSQL):
DB_USER=$(grep "^DB_USERNAME=" "${ENV_FILE}" | cut -d= -f2-)
DB_NAME=$(grep "^DB_DATABASE=" "${ENV_FILE}" | cut -d= -f2-)
DB_PASS=$(grep "^DB_PASSWORD=" "${ENV_FILE}" | cut -d= -f2-)

MYSQL_CID=$(docker compose -f {{DEPLOY_PATH}}/docker-compose.prod.yaml ps -q mysql)
[ -n "${MYSQL_CID}" ] || { echo "ERROR: mysql container not running"; exit 1; }

docker exec "${MYSQL_CID}" \
  mysqldump -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
  | gzip > "${BACKUP_FILE}"

# Retain last 7 days
find "${BACKUP_DIR}" -name "db_*.sql.gz" -mtime +7 -delete

echo "Backup complete: ${BACKUP_FILE}"
BACKUP_EOF

sudo chmod +x "${BACKUP_SCRIPT}"

# Schedule daily backup at 02:00 UTC
CRON_LINE="0 2 * * * ${BACKUP_SCRIPT} >> /var/log/db-backup-{{APP_NAME_SLUG}}.log 2>&1"
if sudo crontab -l 2>/dev/null | grep -qF "${BACKUP_SCRIPT}"; then
  log "Backup cron job already exists"
else
  log "Adding backup cron job (daily at 02:00 UTC)..."
  (sudo crontab -l 2>/dev/null; echo "${CRON_LINE}") | sudo crontab -
fi

# ---------------------------------------------------------------
# 9. Configure host nginx for {{PROD_DOMAIN}}
# ---------------------------------------------------------------
if ! command -v nginx &>/dev/null; then
  log "Installing nginx..."
  sudo apt-get install -y nginx
fi

log "Updating host nginx config for {{PROD_DOMAIN}}..."

if [ -f "${NGINX_AVAILABLE}" ]; then
  sudo cp "${NGINX_AVAILABLE}" "${NGINX_AVAILABLE}.bak.$(date +%Y%m%d%H%M%S)"
fi

sudo cp "${DEPLOY_DIR}/.github/setup/nginx-host.conf" "${NGINX_AVAILABLE}"

if [ ! -L "${NGINX_ENABLED}" ]; then
  sudo ln -s "${NGINX_AVAILABLE}" "${NGINX_ENABLED}"
fi

sudo nginx -t || die "nginx config test failed — review ${NGINX_AVAILABLE}"
sudo systemctl reload nginx

# ---------------------------------------------------------------
# 10. Obtain SSL certificate via Certbot
# ---------------------------------------------------------------
if [ -d "/etc/letsencrypt/live/{{PROD_DOMAIN}}" ]; then
  log "SSL certificate already exists for {{PROD_DOMAIN}}"
else
  log "Obtaining SSL certificate..."
  sudo apt-get install -y certbot python3-certbot-nginx
  SECURITY_EMAIL=$(grep '^SECURITY_EMAIL=' "${DEPLOY_DIR}/.env" | cut -d= -f2- | tr -d '"')
  CERTBOT_EMAIL="${SECURITY_EMAIL:-admin@{{PROD_DOMAIN}}}"
  sudo certbot certonly --nginx -d {{PROD_DOMAIN}} --non-interactive --agree-tos \
    -m "${CERTBOT_EMAIL}" \
    || warn "Certbot failed — ensure DNS resolves to this server first"
  sudo nginx -t && sudo systemctl reload nginx
fi

# ---------------------------------------------------------------
# Done
# ---------------------------------------------------------------
log ""
log "============================================================"
log " Server setup complete!"
log " App:    https://{{PROD_DOMAIN}}"
log " Health: curl -si https://{{PROD_DOMAIN}}/up"
log " Logs:   docker compose -f ${DEPLOY_DIR}/docker-compose.prod.yaml logs -f"
log "============================================================"
