# vscode role

Installs VS Code extensions listed in `vscode_extensions`.

The role **gracefully skips** if the `code` CLI is not found in PATH or if the extension list is empty — it will never fail a run because VS Code isn't installed.

## Requirements

- VS Code installed with the `code` CLI accessible in PATH.
  - On macOS: open VS Code → Command Palette → **Shell Command: Install 'code' command in PATH**.
  - After that, `code --version` should work in a new terminal.

## Variables

| Variable            | Default  | Description                                          |
|---------------------|----------|------------------------------------------------------|
| `vscode_extensions` | `[]`     | List of extension IDs to install                     |
| `vscode_cli`        | `"code"` | CLI executable name (use `"codium"` for VSCodium)    |

## Example Configuration

In `group_vars/all.yml`:

```yaml
vscode_extensions:
  - ms-python.python
  - esbenp.prettier-vscode
  - dbaeumer.vscode-eslint
  - vscodevim.vim
  - eamodio.gitlens
  - ms-azuretools.vscode-docker
```

To get your current extension list:

```bash
code --list-extensions
```

## Notes

- `code --install-extension` is idempotent but always reports "changed" — this is a VS Code CLI limitation.
- If you use [VSCodium](https://vscodium.com/) instead of VS Code, set `vscode_cli: "codium"` in `group_vars/all.yml`.
- Extensions are installed to the default VS Code profile. Per-profile extension management is not supported in v1.
