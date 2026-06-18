#!/usr/bin/env bash
# tests/test_template.sh
# ─────────────────────────────────────────────────────────────────────────────
# Smoke test: verify that site.yml passes ansible-playbook --syntax-check.
#
# This test proves the starter template is valid Ansible before a user forks
# it and starts customising. Run it in CI or locally after making changes.
#
# Usage:
#   bash tests/test_template.sh
#
# Exit codes:
#   0 — syntax check passed
#   1 — syntax check failed (see output above)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Tailor Template Smoke Test ==="
echo "Repo: $REPO_ROOT"
echo ""

# ── Preflight: ensure ansible-playbook is available ──────────────────────────
if ! command -v ansible-playbook &>/dev/null; then
  echo "[ERROR] ansible-playbook not found in PATH."
  echo "        Install Ansible: pip install ansible  OR  brew install ansible"
  exit 1
fi

echo "[INFO] Ansible version: $(ansible-playbook --version | head -1)"
echo ""

# ── Test: ansible-playbook --syntax-check ────────────────────────────────────
echo "[TEST] ansible-playbook --syntax-check site.yml"
cd "$REPO_ROOT"

if ansible-playbook --syntax-check site.yml; then
  echo ""
  echo "[PASS] site.yml passed syntax check."
else
  echo ""
  echo "[FAIL] site.yml failed syntax check — see output above."
  exit 1
fi

echo ""
echo "=== ALL TESTS PASSED ==="
