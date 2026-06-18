#!/usr/bin/env bash
# roles/hooks/pre-apply.sh
# ─────────────────────────────────────────────────────────────────────────────
# Pre-apply hook — runs BEFORE the Tailor playbook starts.
#
# This file is a no-op placeholder. Edit it to add setup steps that must
# happen before Ansible runs (e.g., unlocking a secrets store).
#
# Exit code:
#   0  — hook succeeded, playbook continues
#   >0 — hook failed, playbook is aborted
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Examples (uncomment to use) ───────────────────────────────────────────────

# Sign in to 1Password CLI and export the session token:
# eval "$(op signin)"

# Pull latest secrets from pass:
# pass git pull

# Ensure Homebrew is up to date before install:
# brew update

# ── Placeholder ───────────────────────────────────────────────────────────────
echo "[hooks] pre-apply.sh: no pre-apply steps configured."
