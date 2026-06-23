#!/usr/bin/env bash
# =============================================================================
# update.sh — Pull the latest changes and re-install
#
# Run from the repo root:
#   bash update.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[update] Pulling latest changes..."
git -C "${REPO_DIR}" pull --ff-only

echo "[update] Re-installing..."
bash "${REPO_DIR}/install.sh"
