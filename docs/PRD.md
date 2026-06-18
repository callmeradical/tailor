# PRD: Tailor — Personal System Configuration Manager

## Problem Statement

When a developer switches laptops — whether due to a new company-issued machine, a hardware upgrade, or a fresh OS install — they face hours of manual effort to recreate their environment. Dotfiles are scattered, tool versions differ, preferences are forgotten, and there is no single source of truth for how the machine should be configured. Existing tools like Puppet, Chef, and Ansible are powerful but require significant boilerplate and are not designed around the personal-machine-management use case. There is no lightweight abstraction that makes it easy to declare "this is how my computer should be configured" and apply it repeatably.

## Solution

Tailor is a CLI tool and Ansible-based configuration framework for personal machine management, inspired by Boxen. The user maintains a git repository of valid Ansible roles and playbooks at `~/.config/tailor`. Tailor wraps Ansible with a better CLI experience, a curated starter repo template, and an `adopt` command for capturing ad-hoc changes back into the declared config. A curl-installable bootstrap script gets a fresh machine from zero to fully configured in a single command.

The config repo is a standard Ansible project — `site.yml` as the main playbook, `roles/` for modular configuration, `group_vars/` for variables. Users who know Ansible can read and modify it directly. Users who don't can work through Tailor's CLI and starter roles.

## User Stories

1. As a developer switching to a new laptop, I want to run a single curl command that bootstraps my entire machine, so that I am productive within minutes rather than hours.
2. As a developer, I want the bootstrap script to install Ansible, clone my config repo to `~/.config/tailor`, and run the first apply automatically, so that setup is a single unattended step.
3. As a developer, I want to declare which Homebrew packages and casks should be installed, so that my toolchain is reproducible across machines.
4. As a developer, I want a role that clones my existing dotfiles repo and runs its install script, so that my shell, editor, and tool configs are applied without migrating them into Tailor.
5. As a developer, I want to declare macOS system preferences (dock size, key repeat rate, trackpad settings) using `osx_defaults`, so that they are applied consistently on every fresh install.
6. As a developer, I want to run `tailor apply` to converge my machine to its declared state, so that I can keep any machine up to date as my config evolves.
7. As a developer, I want to run `tailor apply --check` (dry-run), so that I can preview what would change before anything is modified.
8. As a developer, I want to run `tailor apply --role <name>` to apply only a specific role, so that I can iterate quickly without running the full playbook.
9. As a developer, I want to run `tailor adopt brew <package>` to add an already-installed Homebrew package to my declared config, so that ad-hoc installs are captured without manual file editing.
10. As a developer, I want to run `tailor adopt file <path>` to register an existing config file into my dotfiles role, so that one-off customisations are preserved in the config repo.
11. As a developer, I want `tailor adopt` to open the modified config file in my editor after writing it, so that I can review and adjust the change before committing.
12. As a developer, I want to version-control my Tailor config repo in git, so that my machine configuration has a full change history and is recoverable.
13. As a developer, I want clear, readable output during apply showing what changed, what was already correct, and what failed, so that I can trust the apply and diagnose problems quickly.
14. As a developer, I want to validate my playbook before applying with `tailor validate`, so that syntax errors surface before anything is changed on disk.
15. As a developer, I want the starter repo template to include commented-out examples of common roles (packages, dotfiles, macOS prefs, VS Code extensions), so that I can get productive immediately without reading Ansible docs.
16. As a developer, I want Tailor to detect my macOS version automatically and apply the correct `osx_defaults` syntax, so that I do not have to write version conditionals myself.
17. As a developer, I want Tailor to support before/after hooks in the apply lifecycle (plain shell scripts), so that I can run custom steps that Ansible doesn't cover.
18. As a developer, I want the config repo to live at `~/.config/tailor` by default but be overridable via `TAILOR_CONFIG_DIR`, so that it is predictable and fits my existing directory conventions.
19. As a developer, I want `tailor check` to show a diff of what the next apply would change, so that I have a clear picture of machine drift at any time.
20. As a developer, I want the bootstrap script to be idempotent, so that re-running it on an already-configured machine is safe and converges any drift.

## Implementation Decisions

### Modules

**1. Bootstrap Script (`install.sh`)**
A curl-installable shell script. Responsibilities: install Xcode CLI tools, install Homebrew, install Ansible via pip or Homebrew, clone the user's config repo to `~/.config/tailor`, run `tailor apply`. Must be idempotent. Accepts the config repo URL as its only required argument.

**2. CLI (`tailor`)**
The user-facing command. Built as a thin shell wrapper (or Go/Python binary) around `ansible-playbook`. Commands:
- `apply [--check] [--role <name>] [--verbose]` — run `ansible-playbook site.yml` with appropriate flags
- `validate` — run `ansible-playbook --syntax-check`
- `adopt brew <package>` — append package to the Homebrew role vars and open in editor
- `adopt file <path>` — copy file into the dotfiles role and register it, open in editor
- `check` — alias for `apply --check`

**3. Starter Repo Template**
A git repository that users clone as the starting point for their config. Structure:
```
site.yml              # main playbook — includes all roles
roles/
  packages/           # Homebrew formulae + casks
  dotfiles/           # clone dotfiles repo + run installer
  macos-prefs/        # osx_defaults tasks
  vscode/             # extension list
  hooks/              # before/after shell scripts
group_vars/
  all.yml             # user-level variables (dotfiles repo URL, etc.)
```
All roles include commented-out examples. The template is the primary onboarding surface.

**4. Adopt Engine**
The logic behind `tailor adopt`. For `brew`: parses the Homebrew role vars file, appends the new package, writes it back, opens in `$EDITOR`. For `file`: copies the target file into `roles/dotfiles/files/`, adds a symlink task to the role's task list, opens the task file in `$EDITOR`. Must be idempotent (no-op if already declared).

### Architectural Decisions

- **Tailor is Ansible-native.** The config repo is a valid Ansible project. Tailor does not invent a new DSL or compile to Ansible — it IS Ansible, wrapped with a better CLI and a starter template.
- **Single config repo per user.** One git repo, one machine (or many machines sharing the same declared state). Team sharing and per-user overrides are deferred to v2.
- **Dotfiles are referenced, not owned.** Tailor provides a role that clones the user's existing dotfiles repo and runs its installer. It does not manage dotfile content itself.
- **Secrets are out of scope.** Tailor does not handle secrets in v1. The starter template includes a comment pointing to 1Password CLI and Pass as recommended options. A hook point in the apply lifecycle is provided for users to wire in their own secrets solution.
- **No `sync` command.** The workflow is `apply` + `tailor adopt` for individual items. Bulk import of the live machine state is not supported in v1.
- **`adopt` is surgical.** It operates on one package or one file at a time. It always opens the modified file in `$EDITOR` so the user reviews the change before committing.
- **Config location is `~/.config/tailor`.** Overridable via `TAILOR_CONFIG_DIR` env var.

## Testing Decisions

Good tests verify external behavior — what the system produces or does — not internal implementation details.

**What to test:**
- Bootstrap script: given a clean environment fixture, the script installs dependencies and clones the repo without error; re-running it is a no-op.
- CLI `apply --check`: process exits 0, no filesystem modifications occur, expected output is produced.
- CLI `validate`: given a valid playbook, exits 0; given a syntax-broken playbook, exits non-zero with a useful message.
- Adopt engine (brew): given a packages vars file and a new package name, the output vars file contains the new package and is valid YAML; running adopt twice with the same package is a no-op.
- Adopt engine (file): given a dotfiles role and a file path, the file is copied and the task list contains the correct symlink task; idempotent on repeat.
- Starter template: `ansible-playbook --syntax-check` passes on the unmodified template out of the box.

**Testing approach:**
- Unit tests for the adopt engine — pure functions operating on files, easy to test with fixtures.
- Integration tests for the CLI using a temporary directory as `TAILOR_CONFIG_DIR`.
- Smoke test for the bootstrap script in a Docker container (macOS simulation is limited; focus on the Linux path for CI).
- No tests for Ansible role logic itself — that is Ansible's responsibility.

## Out of Scope

- Multi-backend support (Puppet, Chef, Nix) — Tailor is Ansible-only.
- Team/shared config with per-user overrides — personal use only in v1; shareable roles are a v2 concern.
- Secrets management — no integration with 1Password, Pass, Keychain, or env vars in v1.
- Bulk sync / full machine import (`tailor sync`) — replaced by surgical `tailor adopt`.
- Windows support — v1 targets macOS; Linux is a secondary target.
- Remote apply — Tailor always runs locally.
- GUI or web dashboard.
- Package version pinning — use Ansible's native mechanisms if needed.

## Further Notes

- Inspired by Boxen (`github.com/boxen/our-boxen`), which used Puppet the same way Tailor uses Ansible. Boxen was archived in 2018; Tailor is its spiritual successor for the Ansible era.
- The bootstrap experience is the most critical user journey. A developer should be able to go from an unboxed Mac to a fully configured machine by running one curl command and waiting.
- Shareable roles (packages, prefs, tool configs that others can pull in) are the natural v2 extension. The Ansible role structure makes this straightforward — a user can publish roles to Ansible Galaxy or a private git repo and pull them in via a `requirements.yml`.
- Secrets hook point: the starter template's `hooks/pre-apply.sh` is the intended location for users to wire in 1Password CLI (`op signin`) or Pass before the playbook runs.
