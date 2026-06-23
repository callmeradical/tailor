#!/usr/bin/env bash
# install.sh — Tailor bootstrap installer
#
# Supports macOS (Homebrew), Debian/Ubuntu Linux (apt + snap),
# and RHEL/Fedora/CentOS Linux (dnf/yum).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/callmeradical/tailor/main/install.sh | bash -s -- <config-repo-url>
#   bash install.sh <config-repo-url>
#
# Environment variables:
#   TAILOR_CONFIG_DIR   Config directory (default: ~/.config/tailor)
#   TAILOR_SKIP_LINK    Set to 1 to skip symlinking tailor onto PATH (default: 0)

set -euo pipefail

# ---------------------------------------------------------------------------
# OS detection — must be first
# ---------------------------------------------------------------------------

OS="$(uname -s)"    # Darwin | Linux
ARCH="$(uname -m)"  # x86_64 | arm64 | aarch64

case "$OS" in
  Darwin|Linux) ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

# On Linux, detect the distro family for package manager selection.
DISTRO_FAMILY="unknown"
if [[ "$OS" == "Linux" ]]; then
  if command -v apt-get &>/dev/null \
      || grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null \
      || [[ -f /etc/debian_version ]]; then
    DISTRO_FAMILY="debian"
  elif command -v dnf &>/dev/null || command -v yum &>/dev/null \
      || grep -qi "rhel\|fedora\|centos\|rocky\|alma" /etc/os-release 2>/dev/null \
      || [[ -f /etc/redhat-release ]]; then
    DISTRO_FAMILY="rhel"
  else
    DISTRO_FAMILY="linux"
  fi

  # pip --user installs land in ~/.local/bin — add it to PATH now so any
  # previously-installed ansible-playbook is found without a shell reload.
  export PATH="$HOME/.local/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

step() { echo -e "\n${BOLD}==> $*${RESET}"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
info() { echo -e "  ${YELLOW}→${RESET} $*"; }
err()  { echo -e "\n${RED}ERROR: $*${RESET}" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Usage / args
# ---------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
  echo "Usage: bash install.sh <config-repo-url>"
  echo ""
  echo "  config-repo-url  Git URL to your Tailor config repository"
  echo ""
  echo "Example:"
  echo "  curl -fsSL https://raw.githubusercontent.com/callmeradical/tailor/main/install.sh \\"
  echo "    | bash -s -- https://github.com/you/my-tailor-config.git"
  echo ""
  echo "Environment variables:"
  echo "  TAILOR_CONFIG_DIR   Config directory (default: ~/.config/tailor)"
  echo "  TAILOR_SKIP_LINK    Set to 1 to skip symlinking tailor onto PATH"
  exit 1
fi

CONFIG_REPO_URL="$1"
TAILOR_CONFIG_DIR="${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}"
TAILOR_SKIP_LINK="${TAILOR_SKIP_LINK:-0}"

echo ""
echo -e "${BOLD}Tailor Bootstrap Installer${RESET}"
if [[ "$OS" == "Linux" ]]; then
  echo "  OS:          ${OS}/${DISTRO_FAMILY} (${ARCH})"
else
  echo "  OS:          ${OS} (${ARCH})"
fi
echo "  Config repo: ${CONFIG_REPO_URL}"
echo "  Config dir:  ${TAILOR_CONFIG_DIR}"

# ---------------------------------------------------------------------------
# Step 1 — macOS: Xcode Command Line Tools
# ---------------------------------------------------------------------------

if [[ "$OS" == "Darwin" ]]; then
  step "Checking Xcode Command Line Tools"

  if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools already installed ($(xcode-select -p))"
  else
    info "Installing Xcode Command Line Tools..."
    info "A dialog box may appear — click 'Install' to proceed."
    xcode-select --install 2>&1 || true

    echo "  Waiting for installation to complete..."
    local_timeout=0
    until xcode-select -p &>/dev/null; do
      sleep 5
      local_timeout=$((local_timeout + 5))
      [[ $local_timeout -ge 600 ]] \
        && die "Timed out waiting for Xcode CLT. Install manually and re-run."
      echo -n "."
    done
    echo ""
    ok "Xcode Command Line Tools installed"
  fi

  # Accept license silently — suppresses prompts in subsequent steps
  xcodebuild -license status &>/dev/null 2>&1 \
    || sudo xcodebuild -license accept 2>/dev/null \
    || true
fi

# ---------------------------------------------------------------------------
# Step 2 — macOS: Homebrew
# ---------------------------------------------------------------------------

if [[ "$OS" == "Darwin" ]]; then
  step "Checking Homebrew"

  if command -v brew &>/dev/null; then
    ok "Homebrew already installed ($(brew --version | head -1))"
    info "Updating Homebrew..."
    brew update --quiet || info "Homebrew update failed (non-fatal, continuing)"
  else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew installation failed. Check the output above."

    # Add Homebrew to PATH for this session
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi

    ok "Homebrew installed ($(brew --version | head -1))"
  fi
fi

# ---------------------------------------------------------------------------
# Step 2 — Linux: system prerequisites
# ---------------------------------------------------------------------------

if [[ "$OS" == "Linux" ]]; then
  step "Checking system prerequisites"

  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    MISSING_PKGS=()
    for pkg in git curl python3 python3-pip; do
      dpkg -l "$pkg" &>/dev/null 2>&1 || MISSING_PKGS+=("$pkg")
    done
    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
      info "Installing missing packages: ${MISSING_PKGS[*]}"
      sudo apt-get update -qq
      sudo apt-get install -y "${MISSING_PKGS[@]}"
    fi
    ok "Prerequisites available (git, curl, python3, python3-pip)"

  elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    PKG_MGR="dnf"
    command -v dnf &>/dev/null || PKG_MGR="yum"
    info "Installing prerequisites via $PKG_MGR..."
    sudo "$PKG_MGR" install -y git curl python3 python3-pip
    ok "Prerequisites available (git, curl, python3, python3-pip)"

  else
    # Unknown Linux distro — check that required tools exist
    for tool in git curl python3 pip3; do
      command -v "$tool" &>/dev/null \
        || die "'$tool' is required but not installed. Install it and re-run."
    done
    ok "Prerequisites available"
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: Ansible
# ---------------------------------------------------------------------------

step "Checking Ansible"

if command -v ansible-playbook &>/dev/null; then
  ok "Ansible already installed ($(ansible --version | head -1))"
else
  info "Installing Ansible via pip3..."

  if [[ "$OS" == "Linux" ]]; then
    # --user avoids needing sudo and handles "externally-managed" Python envs
    # (Ubuntu 23.04+, Debian 12+). Falls back to --break-system-packages for
    # older pip versions that don't support --user cleanly.
    pip3 install --user --quiet ansible \
      || pip3 install --user --quiet --break-system-packages ansible \
      || die "Ansible installation failed. Ensure python3-pip is installed and try again."
    # Refresh command hash so ansible-playbook in ~/.local/bin is found
    hash -r 2>/dev/null || true
  else
    # macOS: pip3 from Homebrew — no --user flag needed
    pip3 install --quiet ansible \
      || pip3 install --user --quiet ansible \
      || die "Ansible installation failed. Ensure Python 3 and pip3 are available."
    hash -r 2>/dev/null || true
  fi

  ok "Ansible installed ($(ansible --version | head -1))"
fi

step "Checking Ansible community.general collection"

if ansible-galaxy collection list community.general 2>/dev/null | grep -q "community.general"; then
  ok "community.general collection already installed"
else
  info "Installing community.general Ansible collection..."
  ansible-galaxy collection install community.general \
    || die "Failed to install community.general collection."
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
    || die "Failed to update config repo. Resolve conflicts manually and re-run."
  ok "Config repo updated"
elif [[ -d "$TAILOR_CONFIG_DIR" ]] && [[ -n "$(ls -A "$TAILOR_CONFIG_DIR" 2>/dev/null)" ]]; then
  die "Directory ${TAILOR_CONFIG_DIR} exists but is not a git repository. Remove it or set TAILOR_CONFIG_DIR to a different path."
else
  info "Cloning config repo to ${TAILOR_CONFIG_DIR}..."
  git clone "$CONFIG_REPO_URL" "$TAILOR_CONFIG_DIR" \
    || die "Failed to clone config repo from ${CONFIG_REPO_URL}. Check the URL and your SSH keys."
  ok "Config repo cloned to ${TAILOR_CONFIG_DIR}"
fi

# ---------------------------------------------------------------------------
# Step 5: Put tailor on PATH
# ---------------------------------------------------------------------------

step "Installing tailor on PATH"

TAILOR_BIN="${TAILOR_CONFIG_DIR}/bin/tailor"
[[ -f "$TAILOR_BIN" ]] \
  || die "bin/tailor not found in config repo (expected at ${TAILOR_BIN}). Check your config repo structure."
[[ -x "$TAILOR_BIN" ]] || chmod +x "$TAILOR_BIN"

if [[ "$TAILOR_SKIP_LINK" == "1" ]]; then
  info "Skipping symlink (TAILOR_SKIP_LINK=1)"
elif [[ "$OS" == "Darwin" ]]; then
  # Prefer the Homebrew prefix bin (writable by the current user); fall back
  # to /usr/local/bin (writable on Intel, may need sudo on some systems).
  LINK_DIR=""
  if [[ -x /opt/homebrew/bin/brew ]]; then
    LINK_DIR="$(brew --prefix)/bin"
  elif [[ -d /usr/local/bin ]]; then
    LINK_DIR="/usr/local/bin"
  fi

  if [[ -n "$LINK_DIR" ]]; then
    LINK_TARGET="$LINK_DIR/tailor"
    if ln -sf "$TAILOR_BIN" "$LINK_TARGET" 2>/dev/null \
        || sudo ln -sf "$TAILOR_BIN" "$LINK_TARGET" 2>/dev/null; then
      ok "tailor → $LINK_TARGET"
    else
      info "Could not symlink tailor to $LINK_DIR — add ${TAILOR_CONFIG_DIR}/bin to PATH manually."
    fi
  else
    info "Could not determine a suitable bin directory — add ${TAILOR_CONFIG_DIR}/bin to PATH manually."
  fi
else
  # Linux: ~/.local/bin is already on PATH (set at the top of this script)
  mkdir -p "$HOME/.local/bin"
  ln -sf "$TAILOR_BIN" "$HOME/.local/bin/tailor"
  ok "tailor → $HOME/.local/bin/tailor"
fi

# ---------------------------------------------------------------------------
# Step 6: Run tailor apply
# ---------------------------------------------------------------------------

step "Running tailor apply"

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

if [[ "$OS" == "Darwin" ]]; then
  echo "  1. Reload your shell:"
  echo "       source ~/.zshrc"
else
  echo "  1. Reload your shell (ensures ~/.local/bin is in PATH):"
  echo "       source ~/.bashrc"
  echo ""
  echo "     If tailor is not found after reloading, add this to ~/.bashrc:"
  echo '       export PATH="$HOME/.local/bin:$PATH"'
fi

echo ""
echo "  2. Verify your configuration is converged:"
echo "       tailor apply --check"
echo ""
echo "  3. Commit any changes and push:"
echo "       cd ${TAILOR_CONFIG_DIR} && git status"
echo ""
echo "  Re-running this installer is safe — it is fully idempotent."
echo ""
