# macos-prefs role

Applies macOS system preferences using the `community.general.osx_defaults` module — the Ansible equivalent of running `defaults write` from the terminal.

## Requirements

- macOS (role is not meaningful on other platforms).
- `community.general` collection installed:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

## Configured Preferences

| Category    | Setting                  | Default                    |
|-------------|--------------------------|----------------------------|
| Dock        | Autohide                 | `true`                     |
| Dock        | Icon size                | `48` px                    |
| Keyboard    | Key repeat rate          | `2` (fast)                 |
| Keyboard    | Initial key repeat delay | `15` (short)               |
| Trackpad    | Tap-to-click             | `true`                     |
| Screenshots | Save location            | `~/Desktop`                |

## Variables

Override any of these in `group_vars/all.yml`:

| Variable                      | Default             | Description                                         |
|-------------------------------|---------------------|-----------------------------------------------------|
| `macos_dock_autohide`         | `true`              | Hide Dock when not in use                           |
| `macos_dock_tilesize`         | `48`                | Dock icon size in pixels                            |
| `macos_key_repeat`            | `2`                 | Key repeat rate (1 = fastest, higher = slower)      |
| `macos_initial_key_repeat`    | `15`                | Delay before key repeat starts                      |
| `macos_trackpad_tap_to_click` | `true`              | Single-finger tap acts as click                     |
| `macos_screenshot_location`   | `~/Desktop`         | Directory where screenshots are saved               |

## Example Configuration

In `group_vars/all.yml`:

```yaml
macos_dock_autohide: true
macos_dock_tilesize: 36
macos_key_repeat: 1
macos_initial_key_repeat: 10
macos_trackpad_tap_to_click: true
macos_screenshot_location: "{{ ansible_env.HOME }}/Pictures/Screenshots"
```

## Adding More Preferences

Uncomment the example tasks in `tasks/main.yml` or add new `osx_defaults` tasks. To find the domain and key for any preference:

```bash
# Watch what changes when you toggle a setting in System Settings:
defaults read > /tmp/before.txt
# (toggle the setting)
defaults read > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

## Notes

- Changes to Dock and Finder settings require those apps to restart. The role handles this via Ansible handlers automatically.
- Some preferences require a **logout and login** to take full effect (e.g., keyboard settings).
- Key repeat settings take effect for new keystrokes after the next login.
