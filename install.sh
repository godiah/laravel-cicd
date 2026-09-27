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
# 2. Install skill directories
#
# Claude Code only discovers skills laid out as
# ~/.claude/skills/<name>/SKILL.md with YAML frontmatter — a flat
# ~/.claude/skills/<name>.md file is silently ignored. Versions of
# this repo before 2026-09 installed flat files; clean those up too.
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

install_skill_dir() {
  local name="$1"
  local dest_dir="${SKILLS_DIR}/${name}"
  mkdir -p "${dest_dir}"
  install_file "${REPO_DIR}/skills/${name}/SKILL.md" "${dest_dir}/SKILL.md"

  # Remove stale pre-2026-09 flat-file install + its backup, if present.
  if [ -f "${SKILLS_DIR}/${name}.md" ]; then
    rm -f "${SKILLS_DIR}/${name}.md" "${SKILLS_DIR}/${name}.md.bak"
    ok "removed stale flat-file skill ${SKILLS_DIR}/${name}.md (superseded by ${name}/SKILL.md)"
  fi
}

log "Installing skills..."
install_skill_dir "cicd-setup"
install_skill_dir "new-project"
install_skill_dir "rollback"

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
