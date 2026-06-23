# Tailor

**Personal machine configuration management. Ansible-native. Bootstrap from zero with one command.**

Tailor is a declarative system configuration manager for macOS (and Linux) inspired by [Boxen](https://github.com/boxen/our-boxen). You maintain **one git repository** that covers all your machines. On each machine, `tailor apply` pulls from that repo and applies the right configuration automatically — shared packages go on everything, machine-specific packages go only where you declared them.

Switch laptops. Run one command. Done.

---

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/callmeradical/tailor/main/install.sh | bash -s -- https://github.com/yourname/tailor-config.git
```

This installs Ansible, clones your config repo to `~/.config/tailor`, and runs the first apply.

---

## Usage

```sh
tailor apply                   # converge machine to declared state
tailor apply --check           # dry-run — show what would change
tailor apply --role packages   # apply a single role
tailor validate                # syntax-check the playbook
tailor adopt brew ripgrep      # add an installed package to your config
tailor adopt file ~/.zshrc     # register a config file into dotfiles role
```

---

## What you get

A starter repo with five ready-to-configure roles:

| Role | What it does |
|---|---|
| `packages` | Homebrew formulae and casks |
| `dotfiles` | Clones your dotfiles repo and runs its installer |
| `macos-prefs` | Dock, keyboard, trackpad, screenshots via `osx_defaults` |
| `vscode` | VS Code extensions |
| `hooks` | Shell scripts run before and after apply |

The repo covers every machine. Tailor uses `hostname -s` to load the right config automatically — no flags, no manual selection.

```
group_vars/all.yml          ← shared: applied on every machine
host_vars/
  work-mbp/
    main.yml                ← extras for the machine named "work-mbp"
  home-studio/
    main.yml                ← extras for the machine named "home-studio"
```

Use `homebrew_packages_extra` and `homebrew_casks_extra` in your `host_vars` files to add packages on top of the shared base. Defining extras does not replace the shared list — both are installed.

```yaml
# host_vars/work-mbp/main.yml
homebrew_packages_extra:
  - slack
  - zoom
homebrew_casks_extra:
  - 1password
```

See `host_vars/.example-hostname/main.yml` for an annotated template.

The config repo is a standard Ansible project — no new DSL to learn.

---

## Adopt

The `tailor adopt` command captures ad-hoc changes back into your declared config — one item at a time.

```sh
# Installed something on this machine — declare it (machine-specific):
brew install ripgrep
tailor adopt brew ripgrep

# Installed something you want on every machine — declare it shared:
tailor adopt brew --shared git

# Edited a config file — version-control it (shared across machines):
tailor adopt file ~/.gitconfig
```

All adopt commands are idempotent and open the modified file in `$EDITOR` so you can review before committing.

---

## How it works

Tailor is a thin shell wrapper around `ansible-playbook`. The config repo is a valid Ansible project — `site.yml`, `roles/`, `group_vars/`. You can run `ansible-playbook site.yml` directly if you want. Tailor adds:

- A friendlier CLI (`apply`, `check`, `validate`, `adopt`)
- Dev-worktree detection (works in the repo root during development)
- A curated starter template with commented examples

---

## Requirements

- macOS (Linux supported, Windows out of scope)
- Ansible (`pip3 install ansible` or `brew install ansible`)
- `community.general` collection (`ansible-galaxy collection install community.general`)

The `install.sh` bootstrap script handles all of this.

---

## Documentation

Full documentation at **[callmeradical.github.io/tailor](https://callmeradical.github.io/tailor)**

---

## License

MIT
