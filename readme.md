# Tailor

A minimal, Ansible-native personal machine configuration manager. Declare your tools, preferences, and dotfiles in a git repo — apply them to any Mac with a single command.

## How it works

Tailor is a thin shell wrapper around `ansible-playbook`. Your config lives in `~/.config/tailor` (this repo). Running `tailor apply` converges your machine to its declared state.

## Quick start

### Prerequisites

```bash
# Install Homebrew (https://brew.sh) then Ansible
brew install ansible

# Install the community.general collection (provides homebrew module)
ansible-galaxy collection install community.general
```

### Deploy

```bash
# Clone this repo to the expected config location
git clone <your-fork-url> ~/.config/tailor

# (Optional) Make tailor available on your PATH
ln -sf ~/.config/tailor/bin/tailor /usr/local/bin/tailor
```

### Apply your config

```bash
# Dry-run — preview what would change, make no modifications
tailor apply --check

# Apply for real
tailor apply

# Validate playbook syntax only
tailor validate
```

## Repo structure

```
site.yml              # Main playbook — includes all roles
bin/tailor            # CLI wrapper
roles/
  packages/           # Homebrew formulae (community.general.homebrew)
    defaults/main.yml # List of packages to install
    tasks/main.yml    # Install tasks
tests/
  test_tracer.sh      # Tracer bullet smoke test
```

## Declaring packages

Edit `roles/packages/defaults/main.yml`:

```yaml
homebrew_packages:
  - tree
  - ripgrep
  - gh
  - jq
```

Then run `tailor apply` to converge.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TAILOR_CONFIG_DIR` | `~/.config/tailor` | Path to the config repo |

## Running the test suite

```bash
bash tests/test_tracer.sh
```

## Development (worktree)

When running `bin/tailor` from inside the repo directory (e.g., a git worktree during development), the script automatically uses `site.yml` from the repo root instead of `~/.config/tailor`. No symlinks needed for local iteration.

```bash
cd /path/to/tailor-worktree
bash bin/tailor apply --check   # uses ./site.yml
```
