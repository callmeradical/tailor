# packages role

Installs Homebrew formulae (CLI tools) and casks (GUI apps) on macOS.

## Requirements

- Homebrew must be installed on the target machine.
- The `community.general` Ansible collection must be installed:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

## Variables

All variables have defaults in `defaults/main.yml`. Override them in `group_vars/all.yml`.

| Variable            | Default          | Description                              |
|---------------------|------------------|------------------------------------------|
| `homebrew_packages` | `[git, curl, tree]` | List of Homebrew formulae to install  |
| `homebrew_casks`    | `[]`             | List of Homebrew casks to install        |
| `homebrew_taps`     | `[]`             | List of Homebrew taps to add first       |

## Example Configuration

In `group_vars/all.yml`:

```yaml
homebrew_packages:
  - git
  - ripgrep
  - fzf
  - bat
  - gh
  - mise

homebrew_casks:
  - iterm2
  - visual-studio-code
  - 1password

homebrew_taps:
  - homebrew/cask-fonts
```

## Notes

- The role is idempotent — re-running it does not reinstall already-present packages.
- To upgrade a package to its latest version, change `state: present` to `state: latest` in `tasks/main.yml`.
- Cask installation may require your macOS password on first run.
