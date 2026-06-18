# dotfiles role

Clones your dotfiles git repository and runs its installer script.

This role is a **no-op by default** — it does nothing until you set `dotfiles_repo_url` in `group_vars/all.yml`. This makes the starter template safe to run without any configuration.

## How it works

1. Clones your dotfiles repo to `dotfiles_dest` (default: `~/dotfiles`).
2. If an installer script exists at `dotfiles_installer` (default: `install.sh`), runs it with `bash`.
3. Re-running is safe: `git` will pull the latest changes and the installer re-runs.

## Variables

| Variable                | Default                        | Description                                               |
|-------------------------|--------------------------------|-----------------------------------------------------------|
| `dotfiles_repo_url`     | `""`                           | Git URL of your dotfiles repo. **Empty = role is skipped** |
| `dotfiles_dest`         | `~/dotfiles`                   | Where to clone the repo                                   |
| `dotfiles_version`      | `""`                           | Branch/tag/commit to check out (empty = default branch)   |
| `dotfiles_installer`    | `install.sh`                   | Installer script path relative to `dotfiles_dest`         |
| `dotfiles_installer_args` | `""`                         | Arguments passed to the installer                         |

## Example Configuration

In `group_vars/all.yml`:

```yaml
dotfiles_repo_url: "https://github.com/yourname/dotfiles.git"
dotfiles_dest: "{{ ansible_env.HOME }}/dotfiles"
dotfiles_installer: "install.sh"
```

## Notes

- Tailor does **not** manage dotfile content. It only clones and invokes your existing setup.
- If your dotfiles repo uses a `Makefile` instead of a shell script, modify `tasks/main.yml` to use the `community.general.make` module.
- The `install.sh` in your dotfiles repo should itself be idempotent so re-running `tailor apply` is safe.
- For private repos, ensure SSH keys or a deploy token are available before running Tailor.
