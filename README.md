# Dotfiles

Declarative, single-command workstation setup and configuration for **Fedora Kinoite** (and desktop Linux).

## Features

- **Zero OS Layering**: Keeps the base OSTree image pristine; all userland tools run in userspace (`~/.local/bin`, `~/.nvm`, `~/.local/share/flatpak`).
- **Profiles**:
  - `--dev` (default): Full developer workstation (Node LTS via NVM, `gh`, `jq`, `podman-compose`, `oc`, Cursor, Antigravity, Ponytail, work repos).
  - `--desktop`: Minimal desktop essentials (Google Chrome and Insync).
- **Automated Updates**: Systemd user service (`dotfiles-update.service`) running `updown` at login with a 23-hour idempotency guard.
- **Unified AI Prompts**: Self-contained guardrails and instructions in `config/prompts/global.instructions.md` deployed to Cursor and Antigravity.

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
./setup.sh --desktop    # Minimal desktop essentials (Chrome + Insync)
./setup.sh --help       # Show usage and available environment variables
```

| Component | `--desktop` | `--dev` (default) |
|---|---|---|
| Chrome (Flatpak) | ✅ | ✅ |
| Insync (rpm2cpio extraction) | ✅ | ✅ |
| Yakuake (Flatpak + config) | ❌ | ✅ |
| Node.js LTS (via NVM) | ❌ | ✅ |
| CLI Tools (`gh`, `jq`, `podman-compose`, `oc`) | ❌ | ✅ |
| Antigravity Hub & `agy` CLI | ❌ | ✅ |
| Cursor (AppImage) | ❌ | ✅ |
| Ponytail (Cursor + AGY rules) | ❌ | ✅ |
| Work Repositories & SSH Key | ❌ | ✅ |
| Login Auto-Updater | ✅ | ✅ |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `UPDATE` | `0` | Set `UPDATE=1` to force re-downloading CLI binaries |
| `OC_VERSION` | `latest` | Override version tag for `oc` |

## Repository Structure

```
├── setup.sh                           # Main idempotent workstation setup
├── .github/workflows/ci.yml           # ShellCheck & integration tests
├── config/
│   ├── bashrc                         # Shell configuration and aliases
│   ├── gitconfig                      # Global git configuration include
│   ├── prompts/
│   │   └── global.instructions.md     # Unified AI agent instructions & guardrails
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
