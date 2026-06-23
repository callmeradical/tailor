#!/usr/bin/env bash
# tests/test_bootstrap.sh — Integration tests for install.sh
#
# Runs on macOS (the dev machine). Mocks all heavy dependencies so nothing
# is actually installed. A separate Linux mock set simulates the Linux path.
#
# Usage: bash tests/test_bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

PASS=0
FAIL=0
FAILURES=()

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

pass()    { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS + 1)); }
fail()    { echo -e "  ${RED}✗${RESET} $1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }
section() { echo -e "\n${YELLOW}$1${RESET}"; }

CLEANUP_DIRS=()
cleanup() {
  local dir
  for dir in "${CLEANUP_DIRS[@]:-}"; do
    [[ -d "$dir" ]] && rm -rf "$dir" || true
  done
}
trap cleanup EXIT

make_tmpdir() {
  local d
  d="$(mktemp -d)"
  CLEANUP_DIRS+=("$d")
  echo "$d"
}

# ---------------------------------------------------------------------------
# Minimal fake config repo (shared by all tests)
# ---------------------------------------------------------------------------

make_config_repo() {
  local dir
  dir="$(make_tmpdir)"
  mkdir -p "$dir/bin"

  cat > "$dir/bin/tailor" << 'TAILOR_EOF'
#!/usr/bin/env bash
echo "[stub] tailor $*"
exit 0
TAILOR_EOF
  chmod +x "$dir/bin/tailor"

  cat > "$dir/site.yml" << 'YAML_EOF'
---
- hosts: all
  roles: []
YAML_EOF

  git -C "$dir" init -q
  git -C "$dir" add .
  git -C "$dir" -c user.name="Test" -c user.email="test@test.com" commit -q -m "init"
  echo "$dir"
}

# ---------------------------------------------------------------------------
# Mock PATH builder — macOS flavour
# ---------------------------------------------------------------------------

make_macos_mock_bin() {
  local d
  d="$(make_tmpdir)"

  # uname: report Darwin
  cat > "$d/uname" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo "Darwin" ;;
  -m) echo "arm64"  ;;
  *)  /usr/bin/uname "$@" ;;
esac
EOF

  # xcode-select: already installed
  cat > "$d/xcode-select" << 'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-p" ]] && echo "/Library/Developer/CommandLineTools" && exit 0
exit 0
EOF

  # brew: already installed
  cat > "$d/brew" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "Homebrew 4.2.0" ;;
  --prefix)  echo "/opt/homebrew" ;;
  update)    echo "[stub] brew update" ;;
  shellenv)  echo "# homebrew shellenv stub" ;;
  *)         echo "[stub] brew $*" ;;
esac
exit 0
EOF

  # pip3: pretend install succeeds
  cat > "$d/pip3" << 'EOF'
#!/usr/bin/env bash
echo "[stub] pip3 $*"
exit 0
EOF

  # ansible + ansible-playbook + ansible-galaxy: all pre-installed
  cat > "$d/ansible" << 'EOF'
#!/usr/bin/env bash
echo "ansible [core 2.16.0]"
exit 0
EOF

  cat > "$d/ansible-playbook" << 'EOF'
#!/usr/bin/env bash
echo "[stub] ansible-playbook $*"
exit 0
EOF

  cat > "$d/ansible-galaxy" << 'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "collection" && "${2:-}" == "list" ]] \
  && echo "community.general 9.0.0" && exit 0
echo "[stub] ansible-galaxy $*"
exit 0
EOF

  # ln: stub to avoid touching real system dirs
  cat > "$d/ln" << 'EOF'
#!/usr/bin/env bash
echo "[stub] ln $*"
exit 0
EOF

  cat > "$d/curl" << 'EOF'
#!/usr/bin/env bash
echo "[stub] curl $*"
exit 0
EOF

  chmod +x "$d"/*
  echo "$d"
}

# ---------------------------------------------------------------------------
# Mock PATH builder — Linux (Debian/Ubuntu) flavour
# ---------------------------------------------------------------------------

make_linux_mock_bin() {
  local d
  d="$(make_tmpdir)"

  # uname: report Linux
  cat > "$d/uname" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo "Linux"  ;;
  -m) echo "x86_64" ;;
  *)  /usr/bin/uname "$@" ;;
esac
EOF

  # apt-get: stub (pretend it works)
  cat > "$d/apt-get" << 'EOF'
#!/usr/bin/env bash
echo "[stub] apt-get $*"
exit 0
EOF

  # dpkg: pretend all packages are already installed
  cat > "$d/dpkg" << 'EOF'
#!/usr/bin/env bash
echo "[stub] dpkg $*"
exit 0
EOF

  # sudo: just run the command
  cat > "$d/sudo" << 'EOF'
#!/usr/bin/env bash
"$@"
EOF

  # pip3: pretend install succeeds
  cat > "$d/pip3" << 'EOF'
#!/usr/bin/env bash
echo "[stub] pip3 $*"
exit 0
EOF

  # ansible + ansible-playbook + ansible-galaxy: pre-installed
  cat > "$d/ansible" << 'EOF'
#!/usr/bin/env bash
echo "ansible [core 2.16.0]"
exit 0
EOF

  cat > "$d/ansible-playbook" << 'EOF'
#!/usr/bin/env bash
echo "[stub] ansible-playbook $*"
exit 0
EOF

  cat > "$d/ansible-galaxy" << 'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "collection" && "${2:-}" == "list" ]] \
  && echo "community.general 9.0.0" && exit 0
echo "[stub] ansible-galaxy $*"
exit 0
EOF

  # ln: stub
  cat > "$d/ln" << 'EOF'
#!/usr/bin/env bash
echo "[stub] ln $*"
exit 0
EOF

  cat > "$d/curl" << 'EOF'
#!/usr/bin/env bash
echo "[stub] curl $*"
exit 0
EOF

  chmod +x "$d"/*
  echo "$d"
}

# ---------------------------------------------------------------------------
# Runner helpers
# ---------------------------------------------------------------------------

run_install() {
  local mock_bin="$1" config_url="$2" config_dir="$3"
  shift 3
  # Additional env vars passed as "KEY=VALUE" strings
  env PATH="$mock_bin:$PATH" \
      TAILOR_CONFIG_DIR="$config_dir" \
      TAILOR_SKIP_LINK="1" \
      "$@" \
      bash "$INSTALL_SH" "$config_url" 2>&1
}

# ---------------------------------------------------------------------------
# Test 1: Missing argument → non-zero exit + usage message
# ---------------------------------------------------------------------------

section "Test 1: Missing argument"

missing_exit=0
missing_output="$(bash "$INSTALL_SH" 2>&1 || true)"
bash "$INSTALL_SH" 2>/dev/null || missing_exit=$?

if [[ $missing_exit -ne 0 ]]; then
  pass "Exits non-zero when config repo URL missing (exit $missing_exit)"
else
  fail "Should exit non-zero when config repo URL missing"
fi

if echo "$missing_output" | grep -qi "usage"; then
  pass "Prints usage message when argument missing"
else
  fail "Should print usage message when argument missing"
fi

# ---------------------------------------------------------------------------
# Test 2: macOS first-time install — exits 0, config dir populated
# ---------------------------------------------------------------------------

section "Test 2: macOS — first-time install"

MACOS_MOCK="$(make_macos_mock_bin)"
SOURCE_REPO="$(make_config_repo)"
CONFIG_DIR_MAC="$(make_tmpdir)"
rm -rf "$CONFIG_DIR_MAC"

mac_exit=0
mac_output="$(run_install "$MACOS_MOCK" "file://$SOURCE_REPO" "$CONFIG_DIR_MAC")" \
  || mac_exit=$?

if [[ $mac_exit -eq 0 ]]; then
  pass "macOS install exits 0"
else
  fail "macOS install should exit 0 (got $mac_exit)"
  echo "--- output ---"; echo "$mac_output"; echo "--------------"
fi

[[ -d "$CONFIG_DIR_MAC/.git" ]] \
  && pass "Config dir is a git repository" \
  || fail "Config dir should be a git repository"

[[ -f "$CONFIG_DIR_MAC/bin/tailor" ]] \
  && pass "bin/tailor exists in config dir" \
  || fail "bin/tailor should exist in cloned config dir"

echo "$mac_output" | grep -q "bootstrap complete" \
  && pass "Prints completion message" \
  || fail "Should print completion message"

echo "$mac_output" | grep -qi "next steps" \
  && pass "Prints next steps" \
  || fail "Should print next steps"

echo "$mac_output" | grep -qi "zshrc" \
  && pass "macOS next steps mention .zshrc" \
  || fail "macOS next steps should mention .zshrc"

# ---------------------------------------------------------------------------
# Test 3: macOS idempotent re-run
# ---------------------------------------------------------------------------

section "Test 3: macOS — idempotent re-run"

second_exit=0
second_output="$(run_install "$MACOS_MOCK" "file://$SOURCE_REPO" "$CONFIG_DIR_MAC")" \
  || second_exit=$?

if [[ $second_exit -eq 0 ]]; then
  pass "macOS re-run exits 0"
else
  fail "macOS re-run should exit 0 (got $second_exit)"
fi

echo "$second_output" | grep -qi "already" \
  && pass "Re-run detects already-installed components" \
  || fail "Re-run should detect already-installed components"

# ---------------------------------------------------------------------------
# Test 4: Linux first-time install — exits 0, config dir populated
# ---------------------------------------------------------------------------

section "Test 4: Linux — first-time install"

LINUX_MOCK="$(make_linux_mock_bin)"
CONFIG_DIR_LINUX="$(make_tmpdir)"
rm -rf "$CONFIG_DIR_LINUX"

linux_exit=0
linux_output="$(run_install "$LINUX_MOCK" "file://$SOURCE_REPO" "$CONFIG_DIR_LINUX")" \
  || linux_exit=$?

if [[ $linux_exit -eq 0 ]]; then
  pass "Linux install exits 0"
else
  fail "Linux install should exit 0 (got $linux_exit)"
  echo "--- output ---"; echo "$linux_output"; echo "--------------"
fi

[[ -d "$CONFIG_DIR_LINUX/.git" ]] \
  && pass "Linux: config dir is a git repository" \
  || fail "Linux: config dir should be a git repository"

[[ -f "$CONFIG_DIR_LINUX/bin/tailor" ]] \
  && pass "Linux: bin/tailor exists in config dir" \
  || fail "Linux: bin/tailor should exist in cloned config dir"

echo "$linux_output" | grep -q "bootstrap complete" \
  && pass "Linux: prints completion message" \
  || fail "Linux: should print completion message"

echo "$linux_output" | grep -qi "bashrc" \
  && pass "Linux next steps mention .bashrc" \
  || fail "Linux next steps should mention .bashrc"

# macOS-specific steps should not appear in the Linux output
echo "$linux_output" | grep -qi "xcode\|homebrew" \
  && fail "Linux output should not mention Xcode or Homebrew" \
  || pass "Linux output does not mention Xcode or Homebrew"

# ---------------------------------------------------------------------------
# Test 5: Linux idempotent re-run
# ---------------------------------------------------------------------------

section "Test 5: Linux — idempotent re-run"

linux_second_exit=0
linux_second_output="$(run_install "$LINUX_MOCK" "file://$SOURCE_REPO" "$CONFIG_DIR_LINUX")" \
  || linux_second_exit=$?

if [[ $linux_second_exit -eq 0 ]]; then
  pass "Linux re-run exits 0"
else
  fail "Linux re-run should exit 0 (got $linux_second_exit)"
fi

echo "$linux_second_output" | grep -qi "already" \
  && pass "Linux re-run detects already-installed components" \
  || fail "Linux re-run should detect already-installed components"

# ---------------------------------------------------------------------------
# Test 6: TAILOR_CONFIG_DIR override is respected
# ---------------------------------------------------------------------------

section "Test 6: TAILOR_CONFIG_DIR override"

CUSTOM_DIR="$(make_tmpdir)/custom-tailor"
rm -rf "$CUSTOM_DIR"

custom_exit=0
custom_output="$(run_install "$MACOS_MOCK" "file://$SOURCE_REPO" "$CUSTOM_DIR")" \
  || custom_exit=$?

if [[ $custom_exit -eq 0 ]]; then
  pass "Exits 0 with custom TAILOR_CONFIG_DIR"
else
  fail "Should exit 0 with custom TAILOR_CONFIG_DIR (got $custom_exit)"
fi

[[ -d "$CUSTOM_DIR/.git" ]] \
  && pass "Config repo cloned to custom TAILOR_CONFIG_DIR" \
  || fail "Config repo should be cloned to custom TAILOR_CONFIG_DIR"

echo "$custom_output" | grep -q "$CUSTOM_DIR" \
  && pass "Output mentions custom TAILOR_CONFIG_DIR" \
  || fail "Output should mention custom TAILOR_CONFIG_DIR"

# ---------------------------------------------------------------------------
# Test 7: Error handling — bad repo URL exits non-zero
# ---------------------------------------------------------------------------

section "Test 7: Error handling — invalid repo URL"

BAD_DIR="$(make_tmpdir)/bad"
rm -rf "$BAD_DIR"

bad_exit=0
bad_output="$(run_install "$MACOS_MOCK" "file:///nonexistent/repo/path" "$BAD_DIR")" \
  || bad_exit=$?

if [[ $bad_exit -ne 0 ]]; then
  pass "Exits non-zero on bad repo URL (exit $bad_exit)"
else
  fail "Should exit non-zero on bad repo URL"
fi

echo "$bad_output" | grep -qi "error\|failed\|ERROR" \
  && pass "Prints error message on bad repo URL" \
  || fail "Should print error message on bad repo URL"

# ---------------------------------------------------------------------------
# Test 8: Error handling — bin/tailor missing in config repo
# ---------------------------------------------------------------------------

section "Test 8: Error handling — bin/tailor missing"

NOTAILOR_DIR="$(make_tmpdir)"
git -C "$NOTAILOR_DIR" init -q
echo "hello" > "$NOTAILOR_DIR/README.md"
git -C "$NOTAILOR_DIR" add .
git -C "$NOTAILOR_DIR" -c user.name="Test" -c user.email="t@t.com" commit -q -m "init"

NOTAILOR_CONFIG="$(make_tmpdir)/notailor"
rm -rf "$NOTAILOR_CONFIG"

notailor_exit=0
notailor_output="$(run_install "$MACOS_MOCK" "file://$NOTAILOR_DIR" "$NOTAILOR_CONFIG")" \
  || notailor_exit=$?

if [[ $notailor_exit -ne 0 ]]; then
  pass "Exits non-zero when bin/tailor missing (exit $notailor_exit)"
else
  fail "Should exit non-zero when bin/tailor missing"
fi

echo "$notailor_output" | grep -qi "bin/tailor\|not found" \
  && pass "Prints informative error when bin/tailor missing" \
  || fail "Should print informative error when bin/tailor missing"

# ---------------------------------------------------------------------------
# Test 9: RHEL/Fedora first-time install — exits 0
# ---------------------------------------------------------------------------

section "Test 9: RHEL/Fedora — first-time install"

RHEL_MOCK="$(make_linux_mock_bin)"

# Override uname to say Linux and provide dnf mock + /etc/redhat-release stub
cat > "$RHEL_MOCK/dnf" << 'EOF'
#!/usr/bin/env bash
echo "[stub] dnf $*"
exit 0
EOF
chmod +x "$RHEL_MOCK/dnf"

# Write a fake /etc/os-release in the mock dir for detection — not used
# directly, but we can fake the distro via the uname+os-release path.
# Simpler: just provide dnf and no apt-get so the RHEL branch is taken.

CONFIG_DIR_RHEL="$(make_tmpdir)"
rm -rf "$CONFIG_DIR_RHEL"

rhel_exit=0
rhel_output="$(run_install "$RHEL_MOCK" "file://$SOURCE_REPO" "$CONFIG_DIR_RHEL")" \
  || rhel_exit=$?

if [[ $rhel_exit -eq 0 ]]; then
  pass "RHEL/Fedora install exits 0"
else
  fail "RHEL/Fedora install should exit 0 (got $rhel_exit)"
  echo "--- output ---"; echo "$rhel_output"; echo "--------------"
fi

[[ -d "$CONFIG_DIR_RHEL/.git" ]] \
  && pass "RHEL: config dir is a git repository" \
  || fail "RHEL: config dir should be a git repository"

echo "$rhel_output" | grep -q "bootstrap complete" \
  && pass "RHEL: prints completion message" \
  || fail "RHEL: should print completion message"

# ---------------------------------------------------------------------------
# Test 10: Unsupported OS exits non-zero
# ---------------------------------------------------------------------------

section "Test 10: Unsupported OS"

WINDOWS_MOCK="$(make_tmpdir)"
cat > "$WINDOWS_MOCK/uname" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo "Windows_NT" ;;
  *) /usr/bin/uname "$@" ;;
esac
EOF
chmod +x "$WINDOWS_MOCK/uname"

UNSUPPORTED_DIR="$(make_tmpdir)/unsupported"
rm -rf "$UNSUPPORTED_DIR"

unsupported_exit=0
unsupported_output="$(env PATH="$WINDOWS_MOCK:$PATH" \
    TAILOR_CONFIG_DIR="$UNSUPPORTED_DIR" \
    TAILOR_SKIP_LINK="1" \
    bash "$INSTALL_SH" "file://$SOURCE_REPO" 2>&1)" \
  || unsupported_exit=$?

if [[ $unsupported_exit -ne 0 ]]; then
  pass "Exits non-zero on unsupported OS"
else
  fail "Should exit non-zero on unsupported OS"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=============================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "=============================="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  echo ""
  exit 1
else
  echo ""
  echo -e "  ${GREEN}All tests passed!${RESET}"
  echo ""
  exit 0
fi
