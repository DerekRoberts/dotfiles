# Dotfiles

Declarative, single-command workstation setup and configuration for **Fedora Kinoite** (KDE Plasma OSTree).

## Features

- **Zero OS Layering**: Keeps the base OSTree image pristine; all userland tools run in userspace (`~/.local/bin`, `~/.nvm`, `~/.local/share/flatpak`).
- **Two Distinct Profiles**:
  - `setup.sh` (or `--dev`, default): Full developer workstation with CLI toolchain, AI agent environments, Git config & signing, and cloned repositories.
  - `setup.sh --desktop`: Zero-maintenance daily driver for family and friends with no dev tooling or interactive Git prompts.
- **Opinionated Core Desktop (Both Profiles)**:
  - Strict 2-bucket directory layout (`~/Documents` for long-term storage, `~/Downloads` for temporary/scratch files).
  - Spectacle screenshots and video screen recordings route automatically into `~/Downloads`.
  - Left auto-hiding panel (`dodgewindows`, 72px), `DarkestHour` wallpaper, and natural scrolling.
- **Automated Updates**: Systemd user service (`dotfiles-update.service`) running `updown --background` at login with a 23-hour idempotency guard.

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
./setup.sh --desktop    # Minimal desktop essentials for family/friends
./setup.sh --dev        # Explicit dev stack preset
./setup.sh --help       # Show usage and options
```

| Component / Feature | `--desktop` (Family & Friends) | `--dev` / Default (owner) |
|---|:---:|:---:|
| **Desktop Environment** (Spectacle $\to$ Downloads, Left Panel, Natural Scroll) | ✅ | ✅ |
| **Silent OS & App Updates** (`updown` via systemd) | ✅ | ✅ |
| **Essential Desktop Apps** (Chrome, VLC, Insync) | ✅ | ✅ |
| **Git Setup & SSH Commit Signing** (`git-setup.sh`) | ❌ *(Untouched)* | ✅ |
| **Global Git Hooks (gitleaks secret scanning)** | ❌ | ✅ |
| **Developer CLI Suite** (`gh`, `jq`, `gitleaks`, `shellcheck`, `actionlint`, `uv`, `docker-compose`, `oc`, `helm`) | ❌ | ✅ |
| **Node.js LTS** (via NVM) | ❌ | ✅ |
| **AI Assistants & Prompt Rules** (Cursor, Grok Bot, Antigravity Hub, Ponytail) | ❌ | ✅ |
| **Drop-Down Terminal** (Yakuake) | ❌ | ✅ |
| **GitHub Work Repositories** (`~/Repos`) | ❌ | ✅ |


## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `UPDATE` | `0` | Set `UPDATE=1` to re-check GitHub CLI tools (`scripts/setup/dev.sh --tools`), `oc` and `helm` |
| `OC_VERSION` | `latest` | Override version tag for `oc` |
| `HELM_VERSION` | `latest` | Override version tag for `helm` (e.g. `v4.3.1`) |

## AI Agent Guardrails

The rules live in one place each; this README links to them instead of restating them.

- **Policy:** [`config/instructions.md`](config/instructions.md) (Hard Stops, Git & Branch Hygiene, Bot Lanes), plus [`config/personal.md`](config/personal.md) for tone. Skills in [`config/skills/`](config/skills/) load on demand.
- **Reminder hook:** [`config/agent-guard/agent-guard.sh`](config/agent-guard/agent-guard.sh), installed as `~/.local/bin/agent-guard`. It denies the plain forms of the Hard Stops (merges, force-pushes, tags, comments, reviews, reopens, deletes, settings, secrets) and tells the agent to ask the user. A reminder, not a sandbox. The rules read best as examples in [`scripts/test-agent-guard.sh`](scripts/test-agent-guard.sh). Cursor is wired through `config/agent-guard/cursor-hooks.json`; other tools can call `agent-guard shell "<command>" [cwd]` or `agent-guard mcp <tool> <args-json>` from their own pre-command hook.
- **Git hooks:** [`config/hooks/`](config/hooks/), installed to `~/.githooks`: gitleaks on pre-commit, no direct pushes to `main`/`master` on pre-push, and AI `Co-authored-by` trailers dropped on commit-msg.
- **Shell:** [`config/bashrc`](config/bashrc) unsets ambient `GITHUB_TOKEN`/`GH_TOKEN` for agents and restores the user's git identity when a tool rewrites `~/.gitconfig`.

`scripts/setup/ai.sh` concatenates `config/instructions.md` and `config/personal.md` into `~/.local/share/dotfiles/instructions.md` and installs it for each tool:

| Tool | Installed to | Docs |
| :--- | :--- | :--- |
| Antigravity | `~/.gemini/GEMINI.md` | |
| Cursor | `~/.cursor/plugins/local/dotfiles/rules/instructions.mdc` (always-apply plugin rule) | |
| Claude Code | `~/.claude/rules/dotfiles.md` | [User-level rules](https://code.claude.com/docs/en/memory) |
| Kilo | managed block in `~/.config/kilo/AGENTS.md` (other content kept) | [Global instructions](https://kilo.ai/docs/customize/custom-instructions) |

Humans can bypass a hook in an emergency with `git commit --no-verify`, or a shell wrapper with the `command` builtin.

## Supply Chain & Trust Model

This repo's job is downloading and executing third-party software, and
`dotfiles-update.service` does it unattended at graphical login. That makes the
upstreams below part of the trusted computing base: compromise any one of them
and you get code execution on this machine at next login. What is verifiable is
verified; the rest is documented here rather than left implicit.

| Component | Integrity check | Notes |
| --- | --- | --- |
| `oc` | **sha256 verified** | Red Hat publishes `sha256sum.txt` per release; a mismatch aborts the install. |
| `helm` | **sha256 verified** | Downloaded from `get.helm.sh`, which publishes a `.sha256sum` per tarball; a missing checksum or a mismatch aborts the install. |
| `jq`, `gh`, `gitleaks`, `docker-compose`, `shellcheck`, `actionlint`, `uv` | TLS only | GitHub release assets, resolved from the `/releases/latest` redirect. No upstream checksums. Archives are rejected if their members are absolute, traversing, or link outside the extraction directory. |
| Cursor AppImage | TLS + URL anchored | The download URL comes from Cursor's API and must sit under `https://downloads.cursor.com/`. |
| Grok Bot AppImage | User-supplied file | Copied from `~/Downloads/Grok_Bot_*.AppImage` (browser download from `https://x.ai/bot` / `https://cursor.com/download/bot`). No unauthenticated AppImage URL to pin. `.deb`/`.rpm` are unused on Kinoite. |
| Antigravity hub | TLS + URL anchored | URL scraped from the download page, must be under `storage.googleapis.com/antigravity-public/`; archive checked for path traversal. |
| Insync | TLS + URL anchored + digest | URL anchored to `cdn.insynchq.com`. **Insync ships unsigned RPMs** (no `SIGPGP`/`RSAHEADER`), so there is nothing to verify against a key. `rpmkeys --checksig` confirms the package's own digests, and the installed hash is recorded to `~/.local/share/dotfiles/insync.sha256`. |
| `nvm` | Pinned tag | Installer fetched at a resolved release tag, not `main`. |
| Ponytail agent rule | Pinned commit | Pinned by SHA in `dev.sh`, since it becomes standing instructions for every agent session. Bump deliberately after reading the diff. |

Two other deliberate trade-offs:

* **AppImages extract instead of mounting.** Fedora 44 Atomic dropped FUSE 2
  (`libfuse.so.2`). Cursor's launcher passes `--appimage-extract-and-run`.
  Grok Bot rewrites its desktop file on launch to exec
  `~/.local/share/grok-bot/appimage` with no flags, and replaces that path
  with a symlink to the AppImage, so the session sets
  `APPIMAGE_EXTRACT_AND_RUN=1` in `~/.config/environment.d/appimage.conf`.
  It takes effect on the next login. Cursor's launcher, the fallback
  `grok-bot.desktop`, and the `grok-bot` terminal wrapper also pass
  `--no-sandbox` because the AppImage cannot use Chromium's SUID sandbox
  on Kinoite. That gives up renderer isolation: content rendered through
  those launch paths is less contained if a renderer bug is exploited.
  Grok Bot's own AppRun adds `--no-sandbox` only when user namespaces are
  unavailable, so the integrator's menu launcher keeps the sandbox when
  namespaces work.
* **`tpm-enroll.sh` binds to PCR 7 by default**, which measures Secure Boot
  state only — unlocking requires no secret from you, so someone with physical
  access and a kernel Secure Boot already trusts can have the TPM release the
  key. Harden with `TPM2_PIN=yes` (recommended) or `TPM2_PCRS=7+11` to also
  bind the booted kernel, which requires re-running after each kernel update.

## Repository Structure

```
├── setup.sh                           # Main idempotent workstation setup
├── .github/workflows/ci.yml           # ShellCheck & integration tests
├── config/
│   ├── bashrc                         # Shell configuration (copied to ~/.config/dotfiles/bashrc)
│   ├── gitconfig                      # Global git include (copied to ~/.config/dotfiles/gitconfig)
│   ├── hooks/                         # Global git hooks (copied to ~/.githooks)
│   ├── instructions.md                # Unified AI agent instructions & guardrails
│   ├── personal.md                    # Personal tone & taste, appended to instructions.md
│   ├── skills/
│   │   ├── apply-maintenance-mode/    # Draft: take over an app, then maintenance mode
│   │   ├── ci-standards/              # CI and GitHub Actions authoring rules
│   │   ├── cloud-agent-kickoff/       # Standing wishes for cloud-agent handoffs
│   │   ├── derive-uat-checklist/      # UAT checklist and tests from app material
│   │   ├── podman-runner/             # Containerized execution & resource limits
│   │   └── preflight/                 # Ground external prompts against reality
│   ├── kde/
│   │   └── user-places.xbel           # Dolphin sidebar bookmarks
│   ├── systemd/
│   │   └── dotfiles-update.service    # User systemd service for updates
│   └── repos.txt                      # Repositories cloned during dev setup
├── scripts/
│   ├── setup/                         # Modular setup subsystem scripts
│   │   ├── core.sh                    # Shell profiles, XDG dirs, systemd, Dolphin places & MIME defaults
│   │   ├── desktop.sh                 # KDE Plasma layout, panel, notifications & natural scrolling
│   │   ├── apps.sh                    # Application installers (Chrome, VLC, Yakuake, Insync)
│   │   └── dev.sh                     # Toolchains (jq, gh, uv, nvm; `--tools` for CLIs only), AI assistants, oc, helm & repos
│   ├── lib.sh                         # Shared helpers: output, install_copy, download guards
│   ├── updown.sh                      # Workstation updater script (installed to ~/.local/bin/updown)
│   ├── clone-repos.sh                 # Idempotent repository cloner
│   ├── tpm-enroll.sh                  # Optional TPM2 disk unlock helper (see Supply Chain below)
│   ├── update-antigravity.sh          # Runtime updater for Antigravity Hub
│   └── git-setup.sh                   # Interactive git config & signing helper
```
