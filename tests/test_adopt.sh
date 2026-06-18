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

assert_not_contains() {
  local file="$1" pattern="$2" count_expected="$3" label="$4"
  local actual
  actual=$(grep -c "$pattern" "$file" || true)
  if [ "$actual" -le "$count_expected" ]; then
    pass "$label"
  else
    fail "$label (pattern '$pattern' found $actual times, expected <= $count_expected)"
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
  mkdir -p "$tmpdir/roles/packages/vars"
  mkdir -p "$tmpdir/roles/dotfiles/files"
  mkdir -p "$tmpdir/roles/dotfiles/tasks"
  # Minimal vars file
  cat > "$tmpdir/roles/packages/vars/main.yml" << 'YAML'
---
homebrew_packages:
  - git
  - curl
YAML
  # Minimal tasks file
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

# ── adopt brew tests ────────────────────────────────────────────────────────

echo ""
echo "adopt brew"
echo "──────────"

CFGDIR=$(setup_config_dir)

# Test 1: adopt brew adds package to vars file
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew "ripgrep" > /dev/null
assert_contains "$CFGDIR/roles/packages/vars/main.yml" "ripgrep" \
  "adopt brew adds package to vars file"

# Test 2: adopt brew is idempotent (second run does not duplicate)
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew "ripgrep" > /dev/null
COUNT=$(grep -c "ripgrep" "$CFGDIR/roles/packages/vars/main.yml" || true)
if [ "$COUNT" -eq 1 ]; then
  pass "adopt brew is idempotent (second run does not duplicate)"
else
  fail "adopt brew is idempotent (found $COUNT occurrences of 'ripgrep', expected 1)"
fi

# Test 3: adopt brew on already-present package prints message and exits 0
OUTPUT=$(EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR" bash "$ADOPT" brew "ripgrep" 2>&1)
if echo "$OUTPUT" | grep -qi "already"; then
  pass "adopt brew on already-present package prints a message"
else
  fail "adopt brew on already-present package should print message (got: $OUTPUT)"
fi
assert_exits_0 "adopt brew on already-present exits 0" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR' bash '$ADOPT' brew 'ripgrep'"

teardown_config_dir "$CFGDIR"

# Test 4: adopt brew fails if roles/packages does not exist
CFGDIR2=$(mktemp -d)
assert_exits_nonzero "adopt brew fails if roles/packages does not exist" \
  bash -c "EDITOR=cat TAILOR_CONFIG_DIR='$CFGDIR2' bash '$ADOPT' brew 'ripgrep'"
rm -rf "$CFGDIR2"

# ── adopt file tests ────────────────────────────────────────────────────────

echo ""
echo "adopt file"
echo "──────────"

CFGDIR3=$(setup_config_dir)
TMPFILE=$(mktemp /tmp/vimrcXXXX)
echo '"vim config' > "$TMPFILE"
TMPBASENAME=$(basename "$TMPFILE")

# Test 5: adopt file copies file to roles/dotfiles/files/<basename>
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR3" bash "$ADOPT" file "$TMPFILE" > /dev/null
assert_file_exists "$CFGDIR3/roles/dotfiles/files/$TMPBASENAME" \
  "adopt file copies file to roles/dotfiles/files/<basename>"

# Test 6: adopt file adds symlink task to tasks/main.yml
assert_contains "$CFGDIR3/roles/dotfiles/tasks/main.yml" "$TMPBASENAME" \
  "adopt file adds symlink task referencing the file"

# Test 7: adopt file is idempotent
EDITOR=cat TAILOR_CONFIG_DIR="$CFGDIR3" bash "$ADOPT" file "$TMPFILE" > /dev/null
COUNT=$(grep -c "$TMPBASENAME" "$CFGDIR3/roles/dotfiles/tasks/main.yml" || true)
if [ "$COUNT" -le 2 ]; then
  # Allow up to 2 occurrences (name + src lines in one task block)
  pass "adopt file is idempotent (task not duplicated)"
else
  # Count actual task blocks
  TASK_COUNT=$(grep -c "symlink.*$TMPBASENAME\|src.*$TMPBASENAME\|dest.*$TMPBASENAME" "$CFGDIR3/roles/dotfiles/tasks/main.yml" || true)
  if [ "$TASK_COUNT" -le 2 ]; then
    pass "adopt file is idempotent (task not duplicated)"
  else
    fail "adopt file is idempotent (pattern found $COUNT times)"
    cat "$CFGDIR3/roles/dotfiles/tasks/main.yml"
  fi
fi

rm -f "$TMPFILE"
teardown_config_dir "$CFGDIR3"

# Test 8: adopt file fails if roles/dotfiles does not exist
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
