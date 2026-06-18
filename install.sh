#!/usr/bin/env bash
# install.sh — Tailor bootstrap installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/tailor/main/install.sh | bash -s -- <config-repo-url>
#   bash install.sh <config-repo-url>
#
# Environment variables:
#   TAILOR_CONFIG_DIR  Override config directory (default: ~/.config/tailor)

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

step() {
    echo -e "\n${BOLD}==> $*${RESET}"
}

ok() {
    echo -e "  ${GREEN}✓${RESET} $*"
}

info() {
    echo -e "  ${YELLOW}→${RESET} $*"
}

err() {
    echo -e "\n${RED}ERROR: $*${RESET}" >&2
}

die() {
    err "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# Usage check
# ---------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    echo "Usage: bash install.sh <config-repo-url>"
    echo ""
    echo "  config-repo-url  Git URL to your Tailor config repository"
    echo ""
    echo "Example:"
    echo "  bash install.sh https://github.com/you/my-tailor-config.git"
    echo ""
    echo "Environment variables:"
    echo "  TAILOR_CONFIG_DIR  Override config directory (default: ~/.config/tailor)"
    exit 1
fi

CONFIG_REPO_URL="$1"
TAILOR_CONFIG_DIR="${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}"

echo ""
echo -e "${BOLD}Tailor Bootstrap Installer${RESET}"
echo "  Config repo: ${CONFIG_REPO_URL}"
echo "  Config dir:  ${TAILOR_CONFIG_DIR}"

# ---------------------------------------------------------------------------
# Step 1: Xcode Command Line Tools
# ---------------------------------------------------------------------------

step "Checking Xcode Command Line Tools"

if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools already installed ($(xcode-select -p))"
else
    info "Installing Xcode Command Line Tools..."
    info "A dialog box may appear — click 'Install' to proceed."
    xcode-select --install 2>&1 || true

    # Wait for installation to complete
    echo "  Waiting for Xcode Command Line Tools to finish installing..."
    local_timeout=0
    until xcode-select -p &>/dev/null; do
        sleep 5
        local_timeout=$((local_timeout + 5))
        if [[ $local_timeout -ge 600 ]]; then
            die "Xcode Command Line Tools installation timed out after 10 minutes. Please install manually and re-run."
        fi
        echo -n "."
    done
    echo ""
    ok "Xcode Command Line Tools installed"
fi

# Accept Xcode license if needed (suppresses prompts in subsequent steps)
if xcodebuild -license status &>/dev/null 2>&1; then
    : # license already accepted
else
    info "Accepting Xcode license..."
    sudo xcodebuild -license accept 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 2: Homebrew
# ---------------------------------------------------------------------------

step "Checking Homebrew"

if command -v brew &>/dev/null; then
    ok "Homebrew already installed ($(brew --version | head -1))"
    info "Updating Homebrew..."
    brew update --quiet || info "Homebrew update failed (non-fatal, continuing)"
else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || die "Homebrew installation failed. Check the output above."

    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    ok "Homebrew installed ($(brew --version | head -1))"
fi

# ---------------------------------------------------------------------------
# Step 3: Ansible
# ---------------------------------------------------------------------------

step "Checking Ansible"

if command -v ansible-playbook &>/dev/null; then
    ok "Ansible already installed ($(ansible --version | head -1))"
else
    info "Installing Ansible via pip3..."
    pip3 install --quiet ansible \
        || die "Ansible installation via pip3 failed. Ensure Python 3 and pip3 are available."
    ok "Ansible installed ($(ansible --version | head -1))"
fi

step "Checking Ansible community.general collection"

if ansible-galaxy collection list community.general 2>/dev/null | grep -q "community.general"; then
    ok "community.general collection already installed"
else
    info "Installing community.general Ansible collection..."
    ansible-galaxy collection install community.general \
        || die "Failed to install community.general Ansible collection."
    ok "community.general collection installed"
fi

# ---------------------------------------------------------------------------
# Step 4: Clone or update config repo
# ---------------------------------------------------------------------------

step "Setting up Tailor config directory"

mkdir -p "$(dirname "$TAILOR_CONFIG_DIR")"

if [[ -d "$TAILOR_CONFIG_DIR/.git" ]]; then
    ok "Config repo already exists at ${TAILOR_CONFIG_DIR}"
    info "Pulling latest changes..."
    git -C "$TAILOR_CONFIG_DIR" pull --ff-only \
        || die "Failed to update config repo at ${TAILOR_CONFIG_DIR}. Resolve conflicts manually and re-run."
    ok "Config repo updated"
elif [[ -d "$TAILOR_CONFIG_DIR" ]] && [[ -n "$(ls -A "$TAILOR_CONFIG_DIR" 2>/dev/null)" ]]; then
    die "Directory ${TAILOR_CONFIG_DIR} exists but is not a git repository. Remove it or set TAILOR_CONFIG_DIR to a different path."
else
    info "Cloning config repo to ${TAILOR_CONFIG_DIR}..."
    git clone "$CONFIG_REPO_URL" "$TAILOR_CONFIG_DIR" \
        || die "Failed to clone config repo from ${CONFIG_REPO_URL}. Check the URL and your network/SSH keys."
    ok "Config repo cloned to ${TAILOR_CONFIG_DIR}"
fi

# ---------------------------------------------------------------------------
# Step 5: Run tailor apply
# ---------------------------------------------------------------------------

step "Running tailor apply"

TAILOR_BIN="${TAILOR_CONFIG_DIR}/bin/tailor"

if [[ ! -f "$TAILOR_BIN" ]]; then
    die "bin/tailor not found in config repo (expected at ${TAILOR_BIN}). Check your config repo structure."
fi

if [[ ! -x "$TAILOR_BIN" ]]; then
    info "Making bin/tailor executable..."
    chmod +x "$TAILOR_BIN"
fi

info "Running: TAILOR_CONFIG_DIR=${TAILOR_CONFIG_DIR} ${TAILOR_BIN} apply"
TAILOR_CONFIG_DIR="$TAILOR_CONFIG_DIR" "$TAILOR_BIN" apply \
    || die "tailor apply failed. Check the Ansible output above for details."

ok "tailor apply completed successfully"

# ---------------------------------------------------------------------------
# Done — print next steps
# ---------------------------------------------------------------------------

echo ""
echo -e "${GREEN}${BOLD}✓ Tailor bootstrap complete!${RESET}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Reload your shell environment:"
echo "       source ~/.zshrc   # or ~/.bashrc / ~/.bash_profile"
echo ""
echo "  2. Verify your configuration is converged:"
echo "       tailor apply --check"
echo ""
echo "  3. Commit any changes to your config repo and push:"
echo "       cd ${TAILOR_CONFIG_DIR}"
echo "       git status"
echo ""
echo "  If you need to re-run bootstrap at any time, it is safe — the script is idempotent."
echo ""
