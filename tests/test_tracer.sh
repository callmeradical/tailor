#!/usr/bin/env bash
# Tracer bullet test: verify bin/tailor apply --check exits 0
# (ansible syntax check must pass on site.yml)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Tailor Tracer Bullet Test ==="
echo "Repo: $REPO_ROOT"

# Test: bin/tailor apply --check exits 0
echo ""
echo "[TEST] bash bin/tailor apply --check exits 0"
cd "$REPO_ROOT"
if bash bin/tailor apply --check; then
  echo "[PASS] apply --check exited 0"
else
  echo "[FAIL] apply --check exited non-zero"
  exit 1
fi

echo ""
echo "=== ALL TESTS PASSED ==="
