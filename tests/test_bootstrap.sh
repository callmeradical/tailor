#!/usr/bin/env bash
# tests/test_bootstrap.sh — Integration tests for install.sh
#
# Usage: bash tests/test_bootstrap.sh
#
# Tests install.sh using a local file:// Git URL and a temp TAILOR_CONFIG_DIR.
# Mocks heavy dependencies (ansible-playbook, pip3, brew, xcode-select) so the
# test suite runs without actually installing anything.

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

PASS=0
FAIL=0
FAILURES=()

# Colour helpers
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

pass() { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${RESET} $1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }

section() { echo -e "\n${YELLOW}$1${RESET}"; }

# Cleanup registry — registered with trap
CLEANUP_DIRS=()

cleanup() {
    local dir
    for dir in "${CLEANUP_DIRS[@]:-}"; do
        [[ -d "$dir" ]] && rm -rf "$dir" || true
    done
    return 0
}
trap cleanup EXIT

make_tmpdir() {
    local d
    d="$(mktemp -d)"
    CLEANUP_DIRS+=("$d")
    echo "$d"
}

# ---------------------------------------------------------------------------
# Build a minimal fake config repo (with bin/tailor)
# ---------------------------------------------------------------------------

make_config_repo() {
    local dir
    dir="$(make_tmpdir)"
    mkdir -p "$dir/bin"

    # Minimal tailor CLI stub — just exits 0
    cat > "$dir/bin/tailor" << 'TAILOR_EOF'
#!/usr/bin/env bash
echo "[stub] tailor $*"
exit 0
TAILOR_EOF
    chmod +x "$dir/bin/tailor"

    # Minimal site.yml
    cat > "$dir/site.yml" << 'YAML_EOF'
---
- hosts: localhost
  roles: []
YAML_EOF

    git -C "$dir" init -q
    git -C "$dir" add .
    git -C "$dir" -c user.name="Test" -c user.email="test@test.com" commit -q -m "init"

    echo "$dir"
}

# ---------------------------------------------------------------------------
# Build a fake PATH directory with mock commands
# ---------------------------------------------------------------------------

make_mock_bin() {
    local mock_dir
    mock_dir="$(make_tmpdir)"

    # Mock xcode-select — pretend tools are already installed
    cat > "$mock_dir/xcode-select" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-p" ]]; then
    echo "/Library/Developer/CommandLineTools"
    exit 0
fi
exit 0
EOF

    # Mock brew — pretend already installed
    cat > "$mock_dir/brew" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version) echo "Homebrew 4.0.0" ;;
    update)    echo "[stub] brew update" ;;
    *)         echo "[stub] brew $*" ;;
esac
exit 0
EOF

    # Mock pip3 — pretend ansible install succeeds
    cat > "$mock_dir/pip3" << 'EOF'
#!/usr/bin/env bash
echo "[stub] pip3 $*"
exit 0
EOF

    # Mock ansible — pretend already installed
    cat > "$mock_dir/ansible" << 'EOF'
#!/usr/bin/env bash
echo "ansible [core 2.15.0]"
exit 0
EOF

    # Mock ansible-playbook
    cat > "$mock_dir/ansible-playbook" << 'EOF'
#!/usr/bin/env bash
echo "[stub] ansible-playbook $*"
exit 0
EOF

    # Mock ansible-galaxy — pretend community.general already installed
    cat > "$mock_dir/ansible-galaxy" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "collection" && "${2:-}" == "list" ]]; then
    echo "community.general 7.0.0"
    exit 0
fi
echo "[stub] ansible-galaxy $*"
exit 0
EOF

    # Mock curl (for Homebrew install, though brew is mocked so it won't call it)
    cat > "$mock_dir/curl" << 'EOF'
#!/usr/bin/env bash
echo "[stub] curl $*"
exit 0
EOF

    # Mock git (preserve real git but also provide stub)
    # We want real git for cloning, so DON'T mock it — just make the others executable
    chmod +x "$mock_dir"/*

    echo "$mock_dir"
}

# ---------------------------------------------------------------------------
# Helper: run install.sh with mocks + given config repo
# ---------------------------------------------------------------------------

run_install() {
    local config_url="$1"
    local config_dir="$2"
    local mock_bin="$3"
    local extra_env="${4:-}"

    # Prepend mock bin to PATH so our stubs take precedence over real tools.
    # Real git is still available because mock_bin has no git.
    env PATH="$mock_bin:$PATH" \
        TAILOR_CONFIG_DIR="$config_dir" \
        $extra_env \
        bash "$INSTALL_SH" "$config_url" 2>&1
}

# ---------------------------------------------------------------------------
# Test 1: Missing argument → non-zero exit + usage message
# ---------------------------------------------------------------------------

section "Test 1: Missing argument"

output="$(bash "$INSTALL_SH" 2>&1 || true)"
exit_code=0
bash "$INSTALL_SH" 2>/dev/null || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    pass "Exits non-zero when config repo URL is missing (exit $exit_code)"
else
    fail "Should exit non-zero when config repo URL is missing"
fi

if echo "$output" | grep -qi "usage"; then
    pass "Prints usage message when argument missing"
else
    fail "Should print usage message when argument missing"
fi

# ---------------------------------------------------------------------------
# Test 2: First-time install — clones repo, exits 0, config dir populated
# ---------------------------------------------------------------------------

section "Test 2: First-time install (fresh machine)"

MOCK_BIN="$(make_mock_bin)"
SOURCE_REPO="$(make_config_repo)"
CONFIG_DIR="$(make_tmpdir)"
# Remove the temp dir so install.sh creates it fresh
rm -rf "$CONFIG_DIR"

output="$(run_install "file://$SOURCE_REPO" "$CONFIG_DIR" "$MOCK_BIN" "")"
exit_code=0
run_install "file://$SOURCE_REPO" "$CONFIG_DIR" "$MOCK_BIN" "" > /dev/null 2>&1 || exit_code=$?
# Re-run to capture fresh state (CONFIG_DIR now already cloned from first run above)
# Let's redo properly:
rm -rf "$CONFIG_DIR"
actual_exit=0
actual_output="$(env PATH="$MOCK_BIN:$PATH" TAILOR_CONFIG_DIR="$CONFIG_DIR" bash "$INSTALL_SH" "file://$SOURCE_REPO" 2>&1)" || actual_exit=$?

if [[ $actual_exit -eq 0 ]]; then
    pass "Exits 0 on successful first-time install"
else
    fail "Should exit 0 on first-time install (got $actual_exit)"
    echo "--- output ---"
    echo "$actual_output"
    echo "--------------"
fi

if [[ -d "$CONFIG_DIR/.git" ]]; then
    pass "Config dir is a git repository"
else
    fail "Config dir should be a git repository after clone"
fi

if [[ -f "$CONFIG_DIR/bin/tailor" ]]; then
    pass "bin/tailor exists in config dir"
else
    fail "bin/tailor should exist in cloned config dir"
fi

if [[ -f "$CONFIG_DIR/site.yml" ]]; then
    pass "site.yml exists in config dir"
else
    fail "site.yml should exist in cloned config dir"
fi

if echo "$actual_output" | grep -q "bootstrap complete"; then
    pass "Prints completion message"
else
    fail "Should print completion message"
fi

if echo "$actual_output" | grep -qi "next steps"; then
    pass "Prints next steps"
else
    fail "Should print next steps"
fi

# ---------------------------------------------------------------------------
# Test 3: Idempotent re-run — config dir already exists, does git pull
# ---------------------------------------------------------------------------

section "Test 3: Idempotent re-run (already configured machine)"

# CONFIG_DIR is already populated from Test 2
second_exit=0
second_output="$(env PATH="$MOCK_BIN:$PATH" TAILOR_CONFIG_DIR="$CONFIG_DIR" bash "$INSTALL_SH" "file://$SOURCE_REPO" 2>&1)" || second_exit=$?

if [[ $second_exit -eq 0 ]]; then
    pass "Exits 0 on re-run (idempotent)"
else
    fail "Should exit 0 on re-run (got $second_exit)"
    echo "--- output ---"
    echo "$second_output"
    echo "--------------"
fi

if echo "$second_output" | grep -qi "already exists\|already installed\|already"; then
    pass "Re-run detects already-installed components"
else
    fail "Re-run should detect already-installed components"
fi

# ---------------------------------------------------------------------------
# Test 4: TAILOR_CONFIG_DIR env override is respected
# ---------------------------------------------------------------------------

section "Test 4: TAILOR_CONFIG_DIR override"

CUSTOM_DIR="$(make_tmpdir)/custom-tailor"
rm -rf "$CUSTOM_DIR"

custom_exit=0
custom_output="$(env PATH="$MOCK_BIN:$PATH" TAILOR_CONFIG_DIR="$CUSTOM_DIR" bash "$INSTALL_SH" "file://$SOURCE_REPO" 2>&1)" || custom_exit=$?

if [[ $custom_exit -eq 0 ]]; then
    pass "Exits 0 with custom TAILOR_CONFIG_DIR"
else
    fail "Should exit 0 with custom TAILOR_CONFIG_DIR (got $custom_exit)"
fi

if [[ -d "$CUSTOM_DIR/.git" ]]; then
    pass "Config repo cloned to custom TAILOR_CONFIG_DIR"
else
    fail "Config repo should be cloned to custom TAILOR_CONFIG_DIR"
fi

if echo "$custom_output" | grep -q "$CUSTOM_DIR"; then
    pass "Output mentions custom TAILOR_CONFIG_DIR path"
else
    fail "Output should mention custom TAILOR_CONFIG_DIR path"
fi

# ---------------------------------------------------------------------------
# Test 5: Error handling — bad repo URL exits non-zero
# ---------------------------------------------------------------------------

section "Test 5: Error handling — invalid repo URL"

BAD_DIR="$(make_tmpdir)/bad-config"
rm -rf "$BAD_DIR"

bad_exit=0
bad_output="$(env PATH="$MOCK_BIN:$PATH" TAILOR_CONFIG_DIR="$BAD_DIR" bash "$INSTALL_SH" "file:///nonexistent/repo/path" 2>&1)" || bad_exit=$?

if [[ $bad_exit -ne 0 ]]; then
    pass "Exits non-zero on bad repo URL (exit $bad_exit)"
else
    fail "Should exit non-zero on bad repo URL"
fi

if echo "$bad_output" | grep -qi "error\|failed\|ERROR"; then
    pass "Prints error message on bad repo URL"
else
    fail "Should print error message on bad repo URL"
fi

# ---------------------------------------------------------------------------
# Test 6: Error handling — bin/tailor missing in config repo
# ---------------------------------------------------------------------------

section "Test 6: Error handling — bin/tailor missing"

NOTAILOR_DIR="$(make_tmpdir)"
git -C "$NOTAILOR_DIR" init -q
echo "hello" > "$NOTAILOR_DIR/README.md"
git -C "$NOTAILOR_DIR" add .
git -C "$NOTAILOR_DIR" -c user.name="Test" -c user.email="t@t.com" commit -q -m "init"

NOTAILOR_CONFIG="$(make_tmpdir)/notailor-config"
rm -rf "$NOTAILOR_CONFIG"

notailor_exit=0
notailor_output="$(env PATH="$MOCK_BIN:$PATH" TAILOR_CONFIG_DIR="$NOTAILOR_CONFIG" bash "$INSTALL_SH" "file://$NOTAILOR_DIR" 2>&1)" || notailor_exit=$?

if [[ $notailor_exit -ne 0 ]]; then
    pass "Exits non-zero when bin/tailor is missing from config repo"
else
    fail "Should exit non-zero when bin/tailor is missing"
fi

if echo "$notailor_output" | grep -qi "bin/tailor\|not found"; then
    pass "Prints informative error when bin/tailor is missing"
else
    fail "Should print informative error when bin/tailor is missing"
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
