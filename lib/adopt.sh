#!/usr/bin/env bash
# tailor adopt engine
#
# Usage:
#   adopt.sh brew [--shared] <package>
#       --shared  Write to group_vars/all.yml (every machine) instead of the
#                 per-machine host_vars/<hostname>/main.yml (default)
#
#   adopt.sh apt [--shared] <package>
#       --shared  Write to group_vars/all.yml instead of host_vars/<hostname>/
#
#   adopt.sh snap [--shared] [--classic] <package>
#       --classic  Mark package as requiring classic confinement
#       --shared   Write to group_vars/all.yml instead of host_vars/<hostname>/
#
#   adopt.sh file <path>

set -euo pipefail

SUBCOMMAND="${1:-}"
shift || true

TAILOR_CONFIG_DIR="${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}"
EDITOR="${EDITOR:-vi}"

die() { echo "error: $*" >&2; exit 1; }

# ── shared Python YAML-append helper ────────────────────────────────────────
#
# Appends <pkg> to the list named <key> in <filepath>.
# Creates the key with a one-item list if it does not already exist.
# Idempotent: exits 0 without writing if the package is already present.
#
# Usage: _yaml_append_to_list <filepath> <key> <pkg>
_yaml_append_to_list() {
  local filepath="$1" key="$2" pkg="$3"

  python3 - "$filepath" "$key" "$pkg" << 'PYEOF'
import sys, re

filepath = sys.argv[1]
key      = sys.argv[2]
pkg      = sys.argv[3]

with open(filepath, 'r') as f:
    content = f.read()

lines = content.splitlines(keepends=True)

# Check idempotency
if re.search(r'^\s*-\s+[\'"]?' + re.escape(pkg) + r'[\'"]?\s*$', content, re.MULTILINE):
    sys.exit(0)

in_list    = False
insert_after = None
key_line   = None

for i, line in enumerate(lines):
    stripped = line.strip()
    if re.match(r'^' + re.escape(key) + r'\s*:', line):
        in_list  = True
        key_line = i
        continue
    if in_list:
        if stripped.startswith('- ') or stripped == '-':
            insert_after = i
        elif stripped and not stripped.startswith('#'):
            break

if key_line is None:
    # Key doesn't exist — append it
    if not content.endswith('\n'):
        content += '\n'
    content += f'\n{key}:\n  - {pkg}\n'
    with open(filepath, 'w') as f:
        f.write(content)
    sys.exit(0)

# Determine indentation from existing items, default to 2 spaces
indent = '  '
if insert_after is not None:
    m = re.match(r'^(\s+)-', lines[insert_after])
    if m:
        indent = m.group(1)

new_line = f'{indent}- {pkg}\n'

if insert_after is not None:
    lines.insert(insert_after + 1, new_line)
else:
    lines.insert(key_line + 1, new_line)

with open(filepath, 'w') as f:
    f.writelines(lines)
PYEOF
}

# ── adopt brew ──────────────────────────────────────────────────────────────

adopt_brew() {
  local shared=0
  local pkg=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --shared) shared=1; shift ;;
      --*)      die "unknown flag '$1' — usage: tailor adopt brew [--shared] <package>" ;;
      *)        pkg="$1"; shift ;;
    esac
  done

  [ -z "$pkg" ] && die "usage: tailor adopt brew [--shared] <package>"

  if [ "$shared" -eq 1 ]; then
    # ── Shared: write to group_vars/all.yml ──────────────────────────────────
    local vars_file="$TAILOR_CONFIG_DIR/group_vars/all.yml"
    [ -f "$vars_file" ] || die "group_vars/all.yml not found at $vars_file — check TAILOR_CONFIG_DIR"

    if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
      echo "tailor: '$pkg' is already in homebrew_packages (shared) — nothing to do"
      exit 0
    fi

    _yaml_append_to_list "$vars_file" "homebrew_packages" "$pkg"
    echo "tailor: added '$pkg' to homebrew_packages (shared — group_vars/all.yml)"
    "$EDITOR" "$vars_file"
  else
    # ── Per-machine: write to host_vars/<hostname>/main.yml ──────────────────
    local hostname
    hostname="$(hostname -s)"
    local host_dir="$TAILOR_CONFIG_DIR/host_vars/$hostname"
    local vars_file="$host_dir/main.yml"

    mkdir -p "$host_dir"

    if [ ! -f "$vars_file" ]; then
      cat > "$vars_file" << YAML
---
# host_vars/$hostname/main.yml
# Per-machine variables for $hostname. Merged on top of group_vars/all.yml.
#
# Use homebrew_packages_extra / homebrew_casks_extra to add to the shared base
# without replacing it. group_vars/all.yml packages are always installed.

homebrew_packages_extra: []
homebrew_casks_extra: []
YAML
    fi

    if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
      echo "tailor: '$pkg' is already in homebrew_packages_extra for $hostname — nothing to do"
      exit 0
    fi

    _yaml_append_to_list "$vars_file" "homebrew_packages_extra" "$pkg"
    echo "tailor: added '$pkg' to homebrew_packages_extra for $hostname (host_vars/$hostname/main.yml)"
    "$EDITOR" "$vars_file"
  fi
}

# ── adopt apt ───────────────────────────────────────────────────────────────

adopt_apt() {
  local shared=0
  local pkg=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --shared) shared=1; shift ;;
      --*)      die "unknown flag '$1' — usage: tailor adopt apt [--shared] <package>" ;;
      *)        pkg="$1"; shift ;;
    esac
  done

  [ -z "$pkg" ] && die "usage: tailor adopt apt [--shared] <package>"

  if [ "$shared" -eq 1 ]; then
    local vars_file="$TAILOR_CONFIG_DIR/group_vars/all.yml"
    [ -f "$vars_file" ] || die "group_vars/all.yml not found at $vars_file — check TAILOR_CONFIG_DIR"

    if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
      echo "tailor: '$pkg' is already in apt_packages (shared) — nothing to do"
      exit 0
    fi

    _yaml_append_to_list "$vars_file" "apt_packages" "$pkg"
    echo "tailor: added '$pkg' to apt_packages (shared — group_vars/all.yml)"
    "$EDITOR" "$vars_file"
  else
    local hostname
    hostname="$(hostname -s)"
    local host_dir="$TAILOR_CONFIG_DIR/host_vars/$hostname"
    local vars_file="$host_dir/main.yml"

    mkdir -p "$host_dir"

    if [ ! -f "$vars_file" ]; then
      cat > "$vars_file" << YAML
---
# host_vars/$hostname/main.yml
# Per-machine variables for $hostname. Merged on top of group_vars/all.yml.

apt_packages_extra: []
snap_packages_extra: []
snap_classic_packages_extra: []
homebrew_packages_extra: []
homebrew_casks_extra: []
YAML
    fi

    if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
      echo "tailor: '$pkg' is already in apt_packages_extra for $hostname — nothing to do"
      exit 0
    fi

    _yaml_append_to_list "$vars_file" "apt_packages_extra" "$pkg"
    echo "tailor: added '$pkg' to apt_packages_extra for $hostname (host_vars/$hostname/main.yml)"
    "$EDITOR" "$vars_file"
  fi
}

# ── adopt snap ──────────────────────────────────────────────────────────────

adopt_snap() {
  local shared=0
  local classic=0
  local pkg=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --shared)  shared=1; shift ;;
      --classic) classic=1; shift ;;
      --*)       die "unknown flag '$1' — usage: tailor adopt snap [--shared] [--classic] <package>" ;;
      *)         pkg="$1"; shift ;;
    esac
  done

  [ -z "$pkg" ] && die "usage: tailor adopt snap [--shared] [--classic] <package>"

  # Determine which variable key to use
  local key
  if [ "$classic" -eq 1 ]; then
    key="snap_classic_packages"
  else
    key="snap_packages"
  fi

  if [ "$shared" -eq 1 ]; then
    local vars_file="$TAILOR_CONFIG_DIR/group_vars/all.yml"
    [ -f "$vars_file" ] || die "group_vars/all.yml not found at $vars_file — check TAILOR_CONFIG_DIR"

    if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
      echo "tailor: '$pkg' is already in ${key} (shared) — nothing to do"
      exit 0
    fi

    _yaml_append_to_list "$vars_file" "$key" "$pkg"
    echo "tailor: added '$pkg' to ${key} (shared — group_vars/all.yml)"
    "$EDITOR" "$vars_file"
  else
    local hostname
    hostname="$(hostname -s)"
    local host_dir="$TAILOR_CONFIG_DIR/host_vars/$hostname"
    local vars_file="$host_dir/main.yml"

    mkdir -p "$host_dir"

    if [ ! -f "$vars_file" ]; then
      cat > "$vars_file" << YAML
---
# host_vars/$hostname/main.yml
# Per-machine variables for $hostname. Merged on top of group_vars/all.yml.

apt_packages_extra: []
snap_packages_extra: []
snap_classic_packages_extra: []
homebrew_packages_extra: []
homebrew_casks_extra: []
YAML
    fi

    local extra_key="${key}_extra"

    if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
      echo "tailor: '$pkg' is already in ${extra_key} for $hostname — nothing to do"
      exit 0
    fi

    _yaml_append_to_list "$vars_file" "$extra_key" "$pkg"
    echo "tailor: added '$pkg' to ${extra_key} for $hostname (host_vars/$hostname/main.yml)"
    "$EDITOR" "$vars_file"
  fi
}

# ── adopt file ──────────────────────────────────────────────────────────────

adopt_file() {
  local src="${1:-}"
  [ -z "$src" ] && die "usage: tailor adopt file <path>"
  [ -f "$src" ] || die "source file not found: $src"

  local dotfiles_dir="$TAILOR_CONFIG_DIR/roles/dotfiles"
  local files_dir="$dotfiles_dir/files"
  local tasks_file="$dotfiles_dir/tasks/main.yml"

  [ -d "$dotfiles_dir" ] || die "roles/dotfiles role not found at $dotfiles_dir — run 'tailor init' first or check TAILOR_CONFIG_DIR"
  [ -f "$tasks_file" ] || die "tasks file not found: $tasks_file"

  local basename
  basename="$(basename "$src")"

  # Determine link destination:
  # Files starting with '.' → link to ~/.<basename>
  # Otherwise → link to ~/.config/<basename>
  local link_dest
  if [[ "$basename" == .* ]]; then
    link_dest="~/$basename"
  else
    link_dest="~/.config/$basename"
  fi

  # Idempotency check
  if grep -qF "$basename" "$tasks_file"; then
    echo "tailor: '$basename' is already registered in dotfiles tasks — nothing to do"
    exit 0
  fi

  cp "$src" "$files_dir/$basename"
  echo "tailor: copied '$src' → $files_dir/$basename"

  cat >> "$tasks_file" << YAML

- name: Symlink $basename
  file:
    src: "{{ role_path }}/files/$basename"
    dest: "$link_dest"
    state: link
YAML

  echo "tailor: added symlink task for '$basename' → $link_dest"
  "$EDITOR" "$tasks_file"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

case "$SUBCOMMAND" in
  brew)
    adopt_brew "$@"
    ;;
  apt)
    adopt_apt "$@"
    ;;
  snap)
    adopt_snap "$@"
    ;;
  file)
    adopt_file "${1:-}"
    ;;
  *)
    die "usage: tailor adopt <brew|apt|snap|file> <argument>"
    ;;
esac
