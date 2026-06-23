#!/usr/bin/env bash
# =============================================================================
# install.sh — Install the Laravel CI/CD skills and templates into Claude Code
#
# Run from the repo root:
#   bash install.sh
#
# Safe to re-run at any time. Existing files are backed up before overwriting.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"
TEMPLATES_DIR="${HOME}/.claude/cicd-templates"

log()  { echo "[install] $*"; }
ok()   { echo "[install] ✓ $*"; }

# ---------------------------------------------------------------
# 1. Create target directories
# ---------------------------------------------------------------
mkdir -p "${SKILLS_DIR}"
mkdir -p "${TEMPLATES_DIR}/workflows"
mkdir -p "${TEMPLATES_DIR}/docker/php"
mkdir -p "${TEMPLATES_DIR}/docker/nginx/conf.d"
mkdir -p "${TEMPLATES_DIR}/setup"

# ---------------------------------------------------------------
# 2. Install skill files
# ---------------------------------------------------------------
install_file() {
  local src="$1"
  local dest="$2"
  if [ -f "${dest}" ]; then
    cp "${dest}" "${dest}.bak"
  fi
  cp "${src}" "${dest}"
  ok "$(basename "${src}") → ${dest}"
}

log "Installing skills..."
install_file "${REPO_DIR}/skills/cicd-setup.md"   "${SKILLS_DIR}/cicd-setup.md"
install_file "${REPO_DIR}/skills/new-project.md"  "${SKILLS_DIR}/new-project.md"
install_file "${REPO_DIR}/skills/rollback.md"      "${SKILLS_DIR}/rollback.md"

# ---------------------------------------------------------------
# 3. Install template files
# ---------------------------------------------------------------
log "Installing templates..."

# Workflows
install_file "${REPO_DIR}/templates/workflows/ci-caller.yml"       "${TEMPLATES_DIR}/workflows/ci-caller.yml"
install_file "${REPO_DIR}/templates/workflows/cd-caller.yml"       "${TEMPLATES_DIR}/workflows/cd-caller.yml"
install_file "${REPO_DIR}/templates/workflows/ci-standalone.yml"   "${TEMPLATES_DIR}/workflows/ci-standalone.yml"
install_file "${REPO_DIR}/templates/workflows/cd-standalone.yml"   "${TEMPLATES_DIR}/workflows/cd-standalone.yml"
install_file "${REPO_DIR}/templates/workflows/cd-production.yml"   "${TEMPLATES_DIR}/workflows/cd-production.yml"

# Docker build files
install_file "${REPO_DIR}/templates/Dockerfile.production"         "${TEMPLATES_DIR}/Dockerfile.production"
install_file "${REPO_DIR}/templates/docker-compose.prod.yaml"      "${TEMPLATES_DIR}/docker-compose.prod.yaml"
install_file "${REPO_DIR}/templates/.dockerignore"                 "${TEMPLATES_DIR}/.dockerignore"

# PHP config
install_file "${REPO_DIR}/templates/docker/php/php.ini"            "${TEMPLATES_DIR}/docker/php/php.ini"
install_file "${REPO_DIR}/templates/docker/php/www.conf"           "${TEMPLATES_DIR}/docker/php/www.conf"
install_file "${REPO_DIR}/templates/docker/php/docker-entrypoint.sh" "${TEMPLATES_DIR}/docker/php/docker-entrypoint.sh"

# Nginx config
install_file "${REPO_DIR}/templates/docker/nginx/nginx.conf"       "${TEMPLATES_DIR}/docker/nginx/nginx.conf"
install_file "${REPO_DIR}/templates/docker/nginx/conf.d/app.conf"  "${TEMPLATES_DIR}/docker/nginx/conf.d/app.conf"

# Server setup
install_file "${REPO_DIR}/templates/setup/server-setup.sh"         "${TEMPLATES_DIR}/setup/server-setup.sh"
install_file "${REPO_DIR}/templates/setup/nginx-host.conf"         "${TEMPLATES_DIR}/setup/nginx-host.conf"
install_file "${REPO_DIR}/templates/setup/rollback.sh"             "${TEMPLATES_DIR}/setup/rollback.sh"
install_file "${REPO_DIR}/templates/setup/secrets-reference.md"    "${TEMPLATES_DIR}/setup/secrets-reference.md"
install_file "${REPO_DIR}/templates/setup/branch-protection.md"    "${TEMPLATES_DIR}/setup/branch-protection.md"

# ---------------------------------------------------------------
# 4. Done
# ---------------------------------------------------------------
echo ""
echo "============================================================"
echo " Installation complete!"
echo ""
echo " Skills installed (3):"
echo "   /cicd-setup    — generate CI/CD files for any Laravel project"
echo "   /new-project   — scaffold a new Laravel project end-to-end"
echo "   /rollback      — roll back a production deployment"
echo ""
echo " Templates: ${TEMPLATES_DIR}/"
echo "============================================================"
