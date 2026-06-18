#!/usr/bin/env bash
# tailor adopt engine
# Usage:
#   adopt.sh brew <package>
#   adopt.sh file <path>

set -euo pipefail

SUBCOMMAND="${1:-}"
ARG="${2:-}"
TAILOR_CONFIG_DIR="${TAILOR_CONFIG_DIR:-$HOME/.config/tailor}"
EDITOR="${EDITOR:-vi}"

die() { echo "error: $*" >&2; exit 1; }

# ── adopt brew ──────────────────────────────────────────────────────────────

adopt_brew() {
  local pkg="$1"
  [ -z "$pkg" ] && die "usage: tailor adopt brew <package>"

  # Write to group_vars/all.yml — the user's primary config file.
  # roles/packages/vars/main.yml must NOT exist; it would override group_vars.
  local vars_file="$TAILOR_CONFIG_DIR/group_vars/all.yml"

  [ -f "$vars_file" ] || die "group_vars/all.yml not found at $vars_file — check TAILOR_CONFIG_DIR"

  # Check if package already present
  if grep -qE "^\s*-\s+['\"]?${pkg}['\"]?\s*$" "$vars_file"; then
    echo "tailor: '$pkg' is already in homebrew_packages — nothing to do"
    exit 0
  fi

  # Append the package under homebrew_packages list
  # Strategy: find the homebrew_packages key and append after the last list item
  # We use a simple approach: append after the last line that is an indented list item
  # under homebrew_packages, or after the homebrew_packages: line if the list is empty.

  # Use Python for reliable YAML-safe append
  python3 - "$vars_file" "$pkg" << 'PYEOF'
import sys, re

filepath = sys.argv[1]
pkg = sys.argv[2]

with open(filepath, 'r') as f:
    content = f.read()

lines = content.splitlines(keepends=True)

# Find the homebrew_packages key
in_brew_list = False
insert_after = None
brew_key_line = None

for i, line in enumerate(lines):
    stripped = line.strip()
    if re.match(r'^homebrew_packages\s*:', line):
        in_brew_list = True
        brew_key_line = i
        continue
    if in_brew_list:
        if stripped.startswith('- ') or stripped == '-':
            insert_after = i
        elif stripped and not stripped.startswith('#'):
            # New key — stop scanning
            break

if brew_key_line is None:
    # homebrew_packages key doesn't exist — append it
    if not content.endswith('\n'):
        content += '\n'
    content += f'\nhomebrew_packages:\n  - {pkg}\n'
    with open(filepath, 'w') as f:
        f.write(content)
    sys.exit(0)

# Determine indentation from existing items or default to 2 spaces
indent = '  '
if insert_after is not None:
    existing = lines[insert_after]
    m = re.match(r'^(\s+)-', existing)
    if m:
        indent = m.group(1)

new_line = f'{indent}- {pkg}\n'

if insert_after is not None:
    lines.insert(insert_after + 1, new_line)
else:
    # homebrew_packages key exists but list is empty — insert after the key line
    lines.insert(brew_key_line + 1, new_line)

with open(filepath, 'w') as f:
    f.writelines(lines)
PYEOF

  echo "tailor: added '$pkg' to homebrew_packages"
  "$EDITOR" "$vars_file"
}

# ── adopt file ──────────────────────────────────────────────────────────────

adopt_file() {
  local src="$1"
  [ -z "$src" ] && die "usage: tailor adopt file <path>"
  [ -f "$src" ] || die "source file not found: $src"

  local dotfiles_dir="$TAILOR_CONFIG_DIR/roles/dotfiles"
  local files_dir="$dotfiles_dir/files"
  local tasks_file="$dotfiles_dir/tasks/main.yml"

  [ -d "$dotfiles_dir" ] || die "roles/dotfiles role not found at $dotfiles_dir — run 'tailor init' first or check TAILOR_CONFIG_DIR"
  [ -f "$tasks_file" ] || die "tasks file not found: $tasks_file"

  local basename
  basename="$(basename "$src")"

  # Determine link destination using dotfiles convention:
  # Files starting with '.' → link to ~/.<basename>
  # Otherwise → link to ~/.config/<basename>
  local link_dest
  if [[ "$basename" == .* ]]; then
    link_dest="~/$basename"
  else
    link_dest="~/.config/$basename"
  fi

  # Check idempotency: is this file already registered?
  if grep -qF "$basename" "$tasks_file"; then
    echo "tailor: '$basename' is already registered in dotfiles tasks — nothing to do"
    exit 0
  fi

  # Copy file
  cp "$src" "$files_dir/$basename"
  echo "tailor: copied '$src' → $files_dir/$basename"

  # Append symlink task to tasks/main.yml
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
    adopt_brew "$ARG"
    ;;
  file)
    adopt_file "$ARG"
    ;;
  *)
    die "usage: tailor adopt <brew|file> <argument>"
    ;;
esac
