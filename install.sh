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
# OS detection
# ---------------------------------------------------------------------------

OS="unknown"
if [[ "$(uname)" == "Darwin" ]]; then
    OS="macos"
elif [[ -f /etc/debian_version ]] || grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    OS="debian"
elif [[ -f /etc/redhat-release ]] || grep -qi "rhel\|fedora\|centos\|rocky\|alma" /etc/os-release 2>/dev/null; then
    OS="rhel"
else
    OS="linux"
fi

echo ""
echo -e "${BOLD}Tailor Bootstrap Installer${RESET}"
echo "  OS detected: ${OS}"

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

echo "  Config repo: ${CONFIG_REPO_URL}"
echo "  Config dir:  ${TAILOR_CONFIG_DIR}"

# ---------------------------------------------------------------------------
# Step 1: Platform prerequisites
# ---------------------------------------------------------------------------

if [[ "$OS" == "macos" ]]; then

    step "Checking Xcode Command Line Tools"

    if xcode-select -p &>/dev/null; then
        ok "Xcode Command Line Tools already installed ($(xcode-select -p))"
    else
        info "Installing Xcode Command Line Tools..."
        info "A dialog box may appear — click 'Install' to proceed."
        xcode-select --install 2>&1 || true

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

    if xcodebuild -license status &>/dev/null 2>&1; then
        :
    else
        info "Accepting Xcode license..."
        sudo xcodebuild -license accept 2>/dev/null || true
    fi

    step "Checking Homebrew"

    if command -v brew &>/dev/null; then
        ok "Homebrew already installed ($(brew --version | head -1))"
        info "Updating Homebrew..."
        brew update --quiet || info "Homebrew update failed (non-fatal, continuing)"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || die "Homebrew installation failed."

        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi

        ok "Homebrew installed ($(brew --version | head -1))"
    fi

elif [[ "$OS" == "debian" ]]; then

    step "Updating apt and installing prerequisites"

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        git curl wget gnupg lsb-release \
        python3 python3-pip python3-venv \
        software-properties-common
    ok "Prerequisites installed"

elif [[ "$OS" == "rhel" ]]; then

    step "Installing prerequisites via dnf/yum"

    if command -v dnf &>/dev/null; then
        sudo dnf install -y git curl wget python3 python3-pip
    else
        sudo yum install -y git curl wget python3 python3-pip
    fi
    ok "Prerequisites installed"

else
    die "Unsupported OS. Tailor currently supports macOS, Ubuntu/Debian, and RHEL/Fedora."
fi

# ---------------------------------------------------------------------------
# Step 2: Ansible
# ---------------------------------------------------------------------------

step "Checking Ansible"

if command -v ansible-playbook &>/dev/null; then
    ok "Ansible already installed ($(ansible --version | head -1))"
else
    if [[ "$OS" == "macos" ]]; then
        info "Installing Ansible via pip3..."
        pip3 install --quiet ansible \
            || die "Ansible installation via pip3 failed."
    elif [[ "$OS" == "debian" ]]; then
        info "Installing Ansible via pip3..."
        # Use pipx or pip3 with --break-system-packages on newer Ubuntu
        pip3 install --quiet ansible --break-system-packages 2>/dev/null \
            || pip3 install --quiet ansible \
            || sudo apt-get install -y ansible
    else
        info "Installing Ansible via pip3..."
        pip3 install --quiet ansible \
            || die "Ansible installation failed."
    fi
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
# Step 3: Clone or update config repo
# ---------------------------------------------------------------------------

step "Setting up Tailor config directory"

mkdir -p "$(dirname "$TAILOR_CONFIG_DIR")"

if [[ -d "$TAILOR_CONFIG_DIR/.git" ]]; then
    ok "Config repo already exists at ${TAILOR_CONFIG_DIR}"
    info "Pulling latest changes..."
    git -C "$TAILOR_CONFIG_DIR" pull --ff-only \
        || die "Failed to update config repo. Resolve conflicts manually and re-run."
    ok "Config repo updated"
elif [[ -d "$TAILOR_CONFIG_DIR" ]] && [[ -n "$(ls -A "$TAILOR_CONFIG_DIR" 2>/dev/null)" ]]; then
    die "Directory ${TAILOR_CONFIG_DIR} exists but is not a git repo. Remove it or set TAILOR_CONFIG_DIR to a different path."
else
    info "Cloning config repo to ${TAILOR_CONFIG_DIR}..."
    git clone "$CONFIG_REPO_URL" "$TAILOR_CONFIG_DIR" \
        || die "Failed to clone config repo from ${CONFIG_REPO_URL}. Check the URL and your SSH keys."
    ok "Config repo cloned to ${TAILOR_CONFIG_DIR}"
fi

# ---------------------------------------------------------------------------
# Step 4: Run tailor apply
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
# Done
# ---------------------------------------------------------------------------

echo ""
echo -e "${GREEN}${BOLD}✓ Tailor bootstrap complete!${RESET}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Reload your shell:"
echo "       source ~/.zshrc   # or ~/.bashrc"
echo ""
echo "  2. Verify configuration is converged:"
echo "       tailor apply --check"
echo ""
echo "  3. Commit any changes and push:"
echo "       cd ${TAILOR_CONFIG_DIR} && git status"
echo ""
echo "  The script is idempotent — safe to re-run at any time."
echo ""
