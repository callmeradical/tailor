#!/usr/bin/env bash
# roles/hooks/post-apply.sh
# ─────────────────────────────────────────────────────────────────────────────
# Post-apply hook — runs AFTER the Tailor playbook completes.
#
# This file is a no-op placeholder. Edit it to add teardown or notification
# steps that should run after all roles have been applied.
#
# Exit code:
#   0  — hook succeeded
#   >0 — hook failed (reported but does not undo applied changes)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Examples (uncomment to use) ───────────────────────────────────────────────

# Reload shell configuration:
# exec "$SHELL" -l

# Send a macOS notification when apply completes:
# osascript -e 'display notification "tailor apply complete" with title "Tailor"'

# Commit any auto-adopted changes to the config repo:
# git -C "${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}" add -A && \
#   git -C "${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}" diff --cached --quiet || \
#   git -C "${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}" commit -m "chore: auto-commit from post-apply hook"

# ── Placeholder ───────────────────────────────────────────────────────────────
echo "[hooks] post-apply.sh: no post-apply steps configured."
