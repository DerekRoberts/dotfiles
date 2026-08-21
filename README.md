# Dotfiles

Declarative, single-command workstation setup and configuration for **Fedora Kinoite** (KDE Plasma OSTree).

## Features

- **Zero OS Layering**: Keeps the base OSTree image pristine; all userland tools run in userspace (`~/.local/bin`, `~/.nvm`, `~/.local/share/flatpak`).
- **Profiles**:
  - `--dev` (default): Full developer workstation (Node LTS via NVM, `gh`, `jq`, `gitleaks`, `shellcheck`, `actionlint`, `uv`, `docker-compose`, `oc`, Cursor, Antigravity, Ponytail, repositories).
  - `--desktop`: Minimal desktop essentials (Google Chrome, VLC, and Insync).
- **Automated Updates**: Systemd user service (`dotfiles-update.service`) running `updown` at login with a 23-hour idempotency guard.
- **Unified AI Instructions & Guardrails**: Self-contained guardrails and instructions in `config/instructions.md` deployed to Cursor and Antigravity, backed by global pre-commit hooks (Gitleaks, regression guardian) and documented in [`docs/guardrails.md`](docs/guardrails.md).

## Quick Start

**Fresh machine (curl bootstrap):**

```bash
curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash
source ~/.bashrc
```

**Already cloned:**

```bash
~/Repos/dotfiles/setup.sh
source ~/.bashrc
```

## Profiles & Presets

```bash
./setup.sh              # Full developer workstation (default)
./setup.sh --dev        # Explicit dev stack preset
./setup.sh --desktop    # Minimal desktop essentials (Chrome + VLC + Insync)
./setup.sh --help       # Show usage and available environment variables
```

| Component | `--desktop` | `--dev` (default) |
|---|---|---|
| Chrome (Flatpak) | ✅ | ✅ |
| VLC Media Player (Flatpak) | ✅ | ✅ |
| Insync (rpm2cpio extraction) | ✅ | ✅ |
| Yakuake (Flatpak + config) | ❌ | ✅ |
| Node.js LTS (via NVM) | ❌ | ✅ |
| CLI Tools (`gh`, `jq`, `gitleaks`, `shellcheck`, `actionlint`, `uv`, `docker-compose`, `oc`) | ❌ | ✅ |
| Antigravity Hub & `agy` CLI | ❌ | ✅ |
| Cursor (AppImage) | ❌ | ✅ |
| Ponytail (Cursor + AGY rules) | ❌ | ✅ |
| Repositories & SSH Key | ❌ | ✅ |
| Login Auto-Updater | ✅ | ✅ |


## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `UPDATE` | `0` | Set `UPDATE=1` to force re-downloading CLI binaries |
| `OC_VERSION` | `latest` | Override version tag for `oc` |

## AI Agent Guardrails & Safety

Autonomous coding agents (Cursor, Antigravity, and CLI runners) operate under strict client-side guardrails enforcing a **human-in-the-loop** workflow:

- **Prompt-Scope Fencing & Behavioral Guidelines**: Defined in [`config/instructions.md`](config/instructions.md) and deployed to `~/.gemini/GEMINI.md` and Cursor global instructions.
- **Global Pre-Commit Hooks**: Configured in `~/.githooks` via [`config/hooks/pre-commit`](config/hooks/pre-commit) to execute Gitleaks secret scanning and block version regressions.
- **Allowed vs. Blocked Policies**: Detailed allowed operations and hard stop prohibitions (blocking `oc`/`kubectl`, tag creation, PR merges/comments under human credentials, force pushes) are documented in [`docs/guardrails.md`](docs/guardrails.md).

## Repository Structure

```
├── setup.sh                           # Main idempotent workstation setup
├── .github/workflows/ci.yml           # ShellCheck & integration tests
├── docs/
│   └── guardrails.md                  # Comprehensive AI agent guardrails documentation
├── config/
│   ├── bashrc                         # Shell configuration and aliases
│   ├── gitconfig                      # Global git configuration include
│   ├── instructions.md                # Unified AI agent instructions & guardrails
│   ├── skills/
│   │   └── typescript-standards/      # Modular agent skills
│   ├── kde/
│   │   └── user-places.xbel           # Dolphin sidebar bookmarks
│   ├── systemd/
│   │   └── dotfiles-update.service    # User systemd service for updates
│   └── repos.txt                      # Repositories cloned during dev setup
├── scripts/
│   ├── updown.sh                      # Workstation updater script (installed to ~/.local/bin/updown)
│   ├── bootstrap-tools.sh             # CLI binary installer (`oc`)
│   ├── clone-repos.sh                 # Idempotent repository cloner
│   ├── tpm-enroll.sh                  # Optional TPM2 disk unlock helper
│   ├── update-antigravity.sh          # Runtime updater for Antigravity Hub
│   └── git-setup.sh                   # Interactive git config & signing helper
```
