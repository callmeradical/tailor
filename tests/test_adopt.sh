#!/usr/bin/env bash
# Tests for tailor adopt engine
# Usage: bash tests/test_adopt.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ADOPT="$ROOT_DIR/lib/adopt.sh"

# Test helpers
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label (pattern '$pattern' not found in $file)"
    echo "    File contents:"
    cat "$file" | sed 's/^/      /'
  fi
}

assert_exits_0() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label (exited non-zero)"
  fi
}

assert_exits_nonzero() {
  local label="$1"
  shift
  if ! "$@" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (exited 0, expected non-zero)"
  fi
}

assert_file_exists() {
  local file="$1" label="$2"
  if [ -f "$file" ]; then
    pass "$label"
  else
    fail "$label (file not found: $file)"
  fi
}

# Create a temp config dir for tests
setup_config_dir() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/group_vars"
  mkdir -p "$tmpdir/roles/dotfiles/files"
  mkdir -p "$tmpdir/roles/dotfiles/tasks"
  cat > "$tmpdir/group_vars/all.yml" << 'YAML'
---
homebrew_packages:
  - git
  - curl
YAML
  cat > "$tmpdir/roles/dotfiles/tasks/main.yml" << 'YAML'
---
- name: Ensure ~/.config exists
  file:
    path: "{{ ansible_env.HOME }}/.config"
    state: directory
YAML
  echo "$tmpdir"
}

teardown_config_dir() {
  rm -rf "$1"
}

HOSTNAME="$(hostname -s)"

# ── adopt brew (machine-specific, default) ──────────────────────────────────

echo ""
echo "adopt brew (default — host_vars/<hostname>/main.yml)"
echo "─────────────────────────────────────────────────────"

CFGDIR=$(setup_config_dir)
HOST_VARS_FILE="$CFGDIR/host_vars/$HOSTNAME/main.yml"

# Test 1: adopt brew creates host_vars/<hostname>/main.yml and adds package
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew "ripgrep" > /dev/null
assert_file_exists "$HOST_VARS_FILE" \
  "adopt brew creates host_vars/<hostname>/main.yml"
assert_contains "$HOST_VARS_FILE" "ripgrep" \
  "adopt brew adds package to homebrew_packages_extra"

# Test 2: adopt brew is idempotent (second run does not duplicate)
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew "ripgrep" > /dev/null
COUNT=$(grep -c "ripgrep" "$HOST_VARS_FILE" || true)
if [ "$COUNT" -eq 1 ]; then
  pass "adopt brew is idempotent (no duplicate)"
else
  fail "adopt brew is idempotent (found $COUNT occurrences of 'ripgrep', expected 1)"
fi

# Test 3: adopt brew on already-present package prints message and exits 0
OUTPUT=$(EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew "ripgrep" 2>&1)
if echo "$OUTPUT" | grep -qi "already"; then
  pass "adopt brew on already-present package prints a message"
else
  fail "adopt brew should print 'already' message (got: $OUTPUT)"
fi
assert_exits_0 "adopt brew on already-present exits 0" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR' bash '$ADOPT' brew 'ripgrep'"

# Test 4: adopt brew does NOT write to group_vars/all.yml
COUNT=$(grep -c "ripgrep" "$CFGDIR/group_vars/all.yml" || true)
if [ "$COUNT" -eq 0 ]; then
  pass "adopt brew (default) does not touch group_vars/all.yml"
else
  fail "adopt brew (default) should not touch group_vars/all.yml"
fi

teardown_config_dir "$CFGDIR"

# ── adopt brew --shared (group_vars/all.yml) ─────────────────────────────────

echo ""
echo "adopt brew --shared (group_vars/all.yml)"
echo "─────────────────────────────────────────"

CFGDIR=$(setup_config_dir)

# Test 5: adopt brew --shared adds to group_vars/all.yml
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew --shared "ripgrep" > /dev/null
assert_contains "$CFGDIR/group_vars/all.yml" "ripgrep" \
  "adopt brew --shared adds package to group_vars/all.yml"

# Test 6: adopt brew --shared is idempotent
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew --shared "ripgrep" > /dev/null
COUNT=$(grep -c "ripgrep" "$CFGDIR/group_vars/all.yml" || true)
if [ "$COUNT" -eq 1 ]; then
  pass "adopt brew --shared is idempotent (no duplicate)"
else
  fail "adopt brew --shared is idempotent (found $COUNT occurrences, expected 1)"
fi

# Test 7: adopt brew --shared does NOT create host_vars file
if [ ! -f "$CFGDIR/host_vars/$HOSTNAME/main.yml" ]; then
  pass "adopt brew --shared does not create host_vars/<hostname>/main.yml"
else
  fail "adopt brew --shared should not create host_vars/<hostname>/main.yml"
fi

teardown_config_dir "$CFGDIR"

# ── adopt brew argument errors ────────────────────────────────────────────────

echo ""
echo "adopt brew — argument errors"
echo "─────────────────────────────"

CFGDIR=$(setup_config_dir)

# Test 8: adopt brew with no package exits non-zero
assert_exits_nonzero "adopt brew with no package exits non-zero" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR' bash '$ADOPT' brew"

# Test 9: adopt brew with unknown flag exits non-zero
assert_exits_nonzero "adopt brew with unknown flag exits non-zero" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR' bash '$ADOPT' brew --unknown ripgrep"

teardown_config_dir "$CFGDIR"

# ── adopt apt (machine-specific, default) ───────────────────────────────────

echo ""
echo "adopt apt (default — host_vars/<hostname>/main.yml)"
echo "─────────────────────────────────────────────────────"

CFGDIR_APT=$(setup_config_dir)
HOST_VARS_APT="$CFGDIR_APT/host_vars/$HOSTNAME/main.yml"

# Test: adopt apt creates host_vars file and adds to apt_packages_extra
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_APT" bash "$ADOPT" apt "htop" > /dev/null
assert_file_exists "$HOST_VARS_APT" \
  "adopt apt creates host_vars/<hostname>/main.yml"
assert_contains "$HOST_VARS_APT" "htop" \
  "adopt apt adds package to apt_packages_extra"

# Test: adopt apt is idempotent
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_APT" bash "$ADOPT" apt "htop" > /dev/null
COUNT=$(grep -c "htop" "$HOST_VARS_APT" || true)
if [ "$COUNT" -eq 1 ]; then
  pass "adopt apt is idempotent (no duplicate)"
else
  fail "adopt apt is idempotent (found $COUNT occurrences, expected 1)"
fi

# Test: does not touch group_vars/all.yml
COUNT=$(grep -c "htop" "$CFGDIR_APT/group_vars/all.yml" || true)
if [ "$COUNT" -eq 0 ]; then
  pass "adopt apt (default) does not touch group_vars/all.yml"
else
  fail "adopt apt (default) should not touch group_vars/all.yml"
fi

teardown_config_dir "$CFGDIR_APT"

echo ""
echo "adopt apt --shared (group_vars/all.yml)"
echo "─────────────────────────────────────────"

CFGDIR_APT2=$(setup_config_dir)
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_APT2" bash "$ADOPT" apt --shared "curl" > /dev/null
assert_contains "$CFGDIR_APT2/group_vars/all.yml" "curl" \
  "adopt apt --shared adds package to group_vars/all.yml"
teardown_config_dir "$CFGDIR_APT2"

# ── adopt snap ───────────────────────────────────────────────────────────────

echo ""
echo "adopt snap (strict confinement)"
echo "─────────────────────────────────"

CFGDIR_SNAP=$(setup_config_dir)
HOST_VARS_SNAP="$CFGDIR_SNAP/host_vars/$HOSTNAME/main.yml"

# Test: adopt snap (strict) writes to snap_packages_extra
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_SNAP" bash "$ADOPT" snap "htop" > /dev/null
assert_file_exists "$HOST_VARS_SNAP" \
  "adopt snap creates host_vars/<hostname>/main.yml"
assert_contains "$HOST_VARS_SNAP" "htop" \
  "adopt snap adds package to snap_packages_extra"

# Test: idempotent
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_SNAP" bash "$ADOPT" snap "htop" > /dev/null
COUNT=$(grep -c "htop" "$HOST_VARS_SNAP" || true)
if [ "$COUNT" -eq 1 ]; then
  pass "adopt snap (strict) is idempotent"
else
  fail "adopt snap (strict) is idempotent (found $COUNT occurrences, expected 1)"
fi

teardown_config_dir "$CFGDIR_SNAP"

echo ""
echo "adopt snap --classic (classic confinement)"
echo "───────────────────────────────────────────"

CFGDIR_SNAP2=$(setup_config_dir)
HOST_VARS_SNAP2="$CFGDIR_SNAP2/host_vars/$HOSTNAME/main.yml"

# Test: adopt snap --classic writes to snap_classic_packages_extra
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_SNAP2" bash "$ADOPT" snap --classic "code" > /dev/null
assert_contains "$HOST_VARS_SNAP2" "code" \
  "adopt snap --classic adds package to snap_classic_packages_extra"
assert_contains "$HOST_VARS_SNAP2" "snap_classic_packages_extra" \
  "adopt snap --classic writes to the classic key, not strict"

teardown_config_dir "$CFGDIR_SNAP2"

echo ""
echo "adopt snap --shared"
echo "────────────────────"

CFGDIR_SNAP3=$(setup_config_dir)
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_SNAP3" bash "$ADOPT" snap --shared "htop" > /dev/null
assert_contains "$CFGDIR_SNAP3/group_vars/all.yml" "htop" \
  "adopt snap --shared adds to group_vars/all.yml"

EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR_SNAP3" bash "$ADOPT" snap --shared --classic "code" > /dev/null
assert_contains "$CFGDIR_SNAP3/group_vars/all.yml" "code" \
  "adopt snap --shared --classic adds to group_vars/all.yml"

teardown_config_dir "$CFGDIR_SNAP3"

# ── adopt apt/snap argument errors ───────────────────────────────────────────

echo ""
echo "adopt apt/snap — argument errors"
echo "──────────────────────────────────"

CFGDIR_ERR=$(setup_config_dir)
assert_exits_nonzero "adopt apt with no package exits non-zero" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR_ERR' bash '$ADOPT' apt"
assert_exits_nonzero "adopt snap with no package exits non-zero" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR_ERR' bash '$ADOPT' snap"
assert_exits_nonzero "adopt apt with unknown flag exits non-zero" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR_ERR' bash '$ADOPT' apt --unknown htop"
teardown_config_dir "$CFGDIR_ERR"

# ── adopt file tests ────────────────────────────────────────────────────────

echo ""
echo "adopt file"
echo "──────────"

CFGDIR3=$(setup_config_dir)
TMPFILE=$(mktemp /tmp/vimrcXXXX)
echo '"vim config' > "$TMPFILE"
TMPBASENAME=$(basename "$TMPFILE")

# Test 10: adopt file copies file to roles/dotfiles/files/<basename>
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR3" bash "$ADOPT" file "$TMPFILE" > /dev/null
assert_file_exists "$CFGDIR3/roles/dotfiles/files/$TMPBASENAME" \
  "adopt file copies file to roles/dotfiles/files/<basename>"

# Test 11: adopt file adds symlink task to tasks/main.yml
assert_contains "$CFGDIR3/roles/dotfiles/tasks/main.yml" "$TMPBASENAME" \
  "adopt file adds symlink task referencing the file"

# Test 12: adopt file is idempotent — second run must not add a second task block.
# One task block contains the basename 3 times (name, src, dest lines), so the
# count after two adopt calls must still be 3 (not 6).
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR3" bash "$ADOPT" file "$TMPFILE" > /dev/null
COUNT=$(grep -c "$TMPBASENAME" "$CFGDIR3/roles/dotfiles/tasks/main.yml" || true)
if [ "$COUNT" -le 3 ]; then
  pass "adopt file is idempotent (task not duplicated)"
else
  fail "adopt file is idempotent (pattern found $COUNT times, expected <= 3)"
fi

rm -f "$TMPFILE"
teardown_config_dir "$CFGDIR3"

# Test 13: adopt file fails if roles/dotfiles does not exist
CFGDIR4=$(mktemp -d)
TMPFILE2=$(mktemp /tmp/testfileXXXX)
assert_exits_nonzero "adopt file fails if roles/dotfiles does not exist" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR4' bash '$ADOPT' file '$TMPFILE2'"
rm -rf "$CFGDIR4" "$TMPFILE2"

# ── dotfile naming convention tests ────────────────────────────────────────

echo ""
echo "adopt file — dotfile naming"
echo "───────────────────────────"

CFGDIR5=$(setup_config_dir)

# A file starting with '.' → link to ~/.<basename>
DOTFILE=$(mktemp /tmp/.zshrcXXXX)
DOTBASENAME=$(basename "$DOTFILE")
echo "# zshrc" > "$DOTFILE"
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR5" bash "$ADOPT" file "$DOTFILE" > /dev/null
assert_contains "$CFGDIR5/roles/dotfiles/tasks/main.yml" "~/$DOTBASENAME" \
  "dotfile starting with '.' links to ~/.<basename>"

# A normal file → link to ~/.config/<basename>
CFGFILE=$(mktemp /tmp/starshipXXXX)
CFGBASENAME=$(basename "$CFGFILE")
echo "# config" > "$CFGFILE"
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR5" bash "$ADOPT" file "$CFGFILE" > /dev/null
assert_contains "$CFGDIR5/roles/dotfiles/tasks/main.yml" "~/.config/$CFGBASENAME" \
  "non-dotfile links to ~/.config/<basename>"

rm -f "$DOTFILE" "$CFGFILE"
teardown_config_dir "$CFGDIR5"

# ── summary ────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
