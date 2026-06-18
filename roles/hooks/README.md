# hooks role

Runs lifecycle hook scripts before and after the Tailor playbook.

This role is **a no-op by default** — if the hook scripts don't exist, nothing happens. The starter template ships with no-op placeholder scripts at `roles/hooks/pre-apply.sh` and `roles/hooks/post-apply.sh` that you can edit.

## How it works

The `hooks` role is called twice in `site.yml`:

```yaml
- role: hooks
  vars:
    hooks_phase: pre    # runs before all other roles

# ... all other roles ...

- role: hooks
  vars:
    hooks_phase: post   # runs after all other roles
```

| Phase | Script                        | When it runs               |
|-------|-------------------------------|----------------------------|
| `pre` | `roles/hooks/pre-apply.sh`    | Before any role is applied |
| `post`| `roles/hooks/post-apply.sh`   | After all roles complete   |

If a script is missing, the role logs a debug message and continues. If a script exists and exits non-zero, the playbook is aborted.

## Editing hook scripts

Open `roles/hooks/pre-apply.sh` or `roles/hooks/post-apply.sh` and add your shell commands. Both files have commented examples.

### Common pre-apply uses

- Unlock secrets store (1Password CLI, Pass, Vault)
- Pull latest secrets before Ansible runs
- Run `brew update` to refresh the formula list

### Common post-apply uses

- Send a macOS notification: `osascript -e 'display notification "done"'`
- Restart shell: `exec "$SHELL" -l`
- Commit any auto-adopted changes back to git

## Example: 1Password pre-apply hook

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sign in to 1Password and export the session token
eval "$(op signin)"
echo "[hooks] Signed in to 1Password."
```

## Notes

- Hook scripts run in the playbook's directory (`~/.config/tailor` by default).
- Scripts must be executable (`chmod +x`) or called via `bash` — the role calls `bash <script>` directly, so the executable bit is not required.
- Secrets injected in `pre-apply.sh` (e.g., `export OP_SESSION_...`) are **not** visible to Ansible tasks. Use Ansible Vault or environment variables set before running `tailor apply` for secrets that Ansible needs directly.
