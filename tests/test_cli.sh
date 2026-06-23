#!/bin/sh
# tests/test_cli.sh — Integration tests for bin/tailor
#
# Tests spin up an isolated TAILOR_CONFIG_DIR fixture so they don't depend on
# the real roles or any installed collections.
#
# Coverage:
#   1. tailor apply --check exits 0 against a minimal playbook
#   2. tailor validate exits 0 against a valid playbook
#   3. tailor validate exits non-zero against a broken playbook
#   4. tailor check (alias) exits 0
#   5. tailor <unknown-command> exits 1
#   6. tailor apply --role <name> passes --tags to ansible-playbook
#   7. tailor with no arguments exits 1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAILOR_BIN="$REPO_ROOT/bin/tailor"

# ── Helpers ──────────────────────────────────────────────────────────────────

PASS=0
FAIL=0

pass() {
  echo "[PASS] $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "[FAIL] $1"
  FAIL=$((FAIL + 1))
}

# Run a test: assert_exit_eq <expected> <description> <command...>
assert_exit_eq() {
  expected="$1"; desc="$2"; shift 2
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [ "$actual" -eq "$expected" ]; then
    pass "$desc (exit $actual)"
  else
    fail "$desc — expected exit $expected, got $actual"
  fi
}

# ── Fixture setup ─────────────────────────────────────────────────────────────

TMPDIR_BASE="$(mktemp -d)"
FIXTURE_DIR="$TMPDIR_BASE/tailor-test-fixture"
mkdir -p "$FIXTURE_DIR"

# Minimal valid playbook: no roles, no tasks — just a localhost play.
cat > "$FIXTURE_DIR/site.yml" <<'YAML'
---
- name: Test play
  hosts: all
  connection: local
  gather_facts: false
  tasks:
    - name: Noop task
      command: echo tailor-test
      changed_when: false
YAML

# Broken playbook for syntax-check failure test
BROKEN_DIR="$TMPDIR_BASE/tailor-broken-fixture"
mkdir -p "$BROKEN_DIR"
cat > "$BROKEN_DIR/site.yml" <<'YAML'
---
- name: Broken play
  hosts: localhost
  this_is_not_valid_yaml_structure: [unclosed
YAML

cleanup() {
  rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# ── Tests ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== tailor CLI tests ==="
echo ""

# 1. apply --check exits 0 (real ansible dry-run, no changes)
assert_exit_eq 0 "apply --check exits 0" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' apply --check"

# 2. validate exits 0 on a valid playbook
assert_exit_eq 0 "validate exits 0 (valid playbook)" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' validate"

# 3. validate exits non-zero on a broken playbook
# (ansible exits non-zero for unparseable YAML)
TAILOR_CONFIG_DIR="$BROKEN_DIR" sh -c "'$TAILOR_BIN' validate" >/dev/null 2>&1 && {
  fail "validate exits non-zero on broken playbook — expected failure but got exit 0"
} || {
  pass "validate exits non-zero on broken playbook"
}

# 4. check (alias for apply --check) exits 0
assert_exit_eq 0 "check alias exits 0" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' check"

# 5. unknown command exits 1
assert_exit_eq 1 "unknown command exits 1" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' frobnicate"

# 6. no arguments exits 1
assert_exit_eq 1 "no arguments exits 1" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN'"

# 7. --help exits 0
assert_exit_eq 0 "help exits 0" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' --help"

# 8. apply --role passes without error (dry-run with tag filter)
assert_exit_eq 0 "apply --check --role packages exits 0" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' apply --check --role packages"

# 9. apply --role missing argument exits 1
assert_exit_eq 1 "apply --role without argument exits 1" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' apply --role"

# 10. apply unknown option exits 1
assert_exit_eq 1 "apply unknown option exits 1" \
  sh -c "TAILOR_CONFIG_DIR='$FIXTURE_DIR' '$TAILOR_BIN' apply --foobar"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
