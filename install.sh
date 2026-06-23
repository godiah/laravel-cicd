#!/usr/bin/env bash
# =============================================================================
# install.sh — Install the Laravel CI/CD skill and templates into Claude Code
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
done() { echo "[install] ✓ $*"; }

# ---------------------------------------------------------------
# 1. Create target directories
# ---------------------------------------------------------------
mkdir -p "${SKILLS_DIR}"
mkdir -p "${TEMPLATES_DIR}/workflows"
mkdir -p "${TEMPLATES_DIR}/docker/php"
mkdir -p "${TEMPLATES_DIR}/docker/nginx/conf.d"
mkdir -p "${TEMPLATES_DIR}/setup"

# ---------------------------------------------------------------
# 2. Install the skill file
# ---------------------------------------------------------------
SKILL_DEST="${SKILLS_DIR}/cicd-setup.md"

if [ -f "${SKILL_DEST}" ]; then
  cp "${SKILL_DEST}" "${SKILL_DEST}.bak"
  log "Backed up existing skill to ${SKILL_DEST}.bak"
fi

cp "${REPO_DIR}/skill.md" "${SKILL_DEST}"
done "Skill installed → ${SKILL_DEST}"

# ---------------------------------------------------------------
# 3. Install template files
# ---------------------------------------------------------------
install_file() {
  local src="$1"
  local dest="$2"
  if [ -f "${dest}" ]; then
    cp "${dest}" "${dest}.bak"
  fi
  cp "${src}" "${dest}"
  done "$(basename "${src}") → ${dest}"
}

# Workflows
install_file "${REPO_DIR}/templates/workflows/ci.yml"              "${TEMPLATES_DIR}/workflows/ci.yml"
install_file "${REPO_DIR}/templates/workflows/cd.yml"              "${TEMPLATES_DIR}/workflows/cd.yml"
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
install_file "${REPO_DIR}/templates/setup/secrets-reference.md"    "${TEMPLATES_DIR}/setup/secrets-reference.md"
install_file "${REPO_DIR}/templates/setup/branch-protection.md"    "${TEMPLATES_DIR}/setup/branch-protection.md"

# ---------------------------------------------------------------
# 4. Done
# ---------------------------------------------------------------
echo ""
echo "============================================================"
echo " Installation complete!"
echo ""
echo " Skill:     ${SKILL_DEST}"
echo " Templates: ${TEMPLATES_DIR}/"
echo ""
echo " Usage: open any Laravel project in Claude Code and run"
echo "        /cicd-setup"
echo "============================================================"
