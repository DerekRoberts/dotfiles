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

| Component / Feature | `--desktop` (Family & Friends) | `--dev` / Default (Derek) |
|---|:---:|:---:|
| **Desktop Environment** (Spectacle $\to$ Downloads, Left Panel, Natural Scroll) | ✅ | ✅ |
| **Silent OS & App Updates** (`updown` via systemd) | ✅ | ✅ |
| **Essential Desktop Apps** (Chrome, VLC, Insync) | ✅ | ✅ |
| **Git Setup & SSH Commit Signing** (`git-setup.sh`) | ❌ *(Untouched)* | ✅ |
| **Global Git Hooks (gitleaks secret scanning)** | ❌ | ✅ |
| **Developer CLI Suite** (`gh`, `jq`, `gitleaks`, `shellcheck`, `actionlint`, `uv`, `docker-compose`, `oc`) | ❌ | ✅ |
| **Node.js LTS** (via NVM) | ❌ | ✅ |
| **AI Assistants & Prompt Rules** (Cursor, Antigravity Hub, `agy`, Ponytail) | ❌ | ✅ |
| **Drop-Down Terminal** (Yakuake) | ❌ | ✅ |
| **GitHub Work Repositories** (`~/Repos`) | ❌ | ✅ |


## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `UPDATE` | `0` | Set `UPDATE=1` to re-check GitHub CLI tools (`scripts/setup/dev.sh --tools`) and `oc` |
| `OC_VERSION` | `latest` | Override version tag for `oc` |

## AI Agent Guardrails & Safety

AI-assisted development accelerates velocity, but autonomous coding agents require strict guardrails to protect shared environments, preserve git history integrity, and maintain compliance.

This repository establishes a client-side safety net and policy framework that enforces a **human-in-the-loop** workflow across all AI tooling (Cursor, Antigravity, and CLI agents).

### Core Philosophy

- **Safety Belt, Not a Sandbox**: Guardrails serve as a safety belt to prevent well-intentioned tools from making automated mistakes. They do not constitute an adversarial security sandbox. Genuine security boundaries must be enforced at the platform level (e.g., GitHub branch protection rules, least-privilege cloud IAM, and CI/CD pipelines).
- **Human-in-the-Loop Lifecycle**: Autonomous agents excel at writing code, generating tests, and drafting pull requests. However, **humans retain sole ownership of critical lifecycle events**:
  - Deploying to or inspecting live infrastructure (`oc`, `kubectl`).
  - Merging pull requests, closing issues, and managing releases or tags.
  - Posting reviews or comments under human credentials (preventing impersonation).
  - Modifying security configurations, repository secrets, or database destruction toggles.
- **Soft Policy vs. Hard Checks**:
  - *Soft Policy (Behavioral Guidelines)*: Structured behavioral constraints, communication standards, and planning expectations live in [`config/instructions.md`](config/instructions.md) and deploy directly to agent prompts (e.g., Cursor, Antigravity).
  - *Hard Checks (Hooks & Guardians)*: Automated verification runs locally via global Git hooks (`~/.githooks/pre-commit`) to block secret leakage and version regressions before commits are recorded.

### Allowed vs. Blocked Matrix

#### What Is Allowed (Agents)

| Tool / Domain | Permitted Actions | Rationale & Context |
| :--- | :--- | :--- |
| **`git`** | `commit`, `push` (non-force), branch creation, `fetch`, `merge origin/main` | Standard feature branch development. |
| **`gh`** | `pr create`, `pr edit`, `pr view`, `pr diff`, read-only `api GET` | Opening and updating pull requests, inspecting review feedback. |
| **Package Managers** (`npm`, `uv`, `pip`, etc.) | Standard package install, build, test, and typecheck commands | Regular dependency resolution without peer dependency bypasses. |
| **Diagnostics & Tests** | Running test suites, linters (`shellcheck`, `actionlint`, `eslint`), and build checks | Verifying code quality and runtime correctness prior to completion. |

#### What Is Blocked (Hard Stops)

| Target / Tool | Blocked Action / Flag | Policy Rationale |
| :--- | :--- | :--- |
| **`oc` / `kubectl`** | All commands and subcommands | Prevents automated cluster access, data leakage, and unintended modifications to live OpenShift/Kubernetes environments. |
| **`git`** | `commit --no-verify`, `commit -n` | Prohibits agents from bypassing local pre-commit hooks and secret scanning. |
| **`git`** | `commit --amend` | Prevents history rewrites on shared or existing commit chains. |
| **`git`** | `config` subcommand | Prevents agents from altering global/local git configurations or disabling safety hooks. |
| **`git`** | write `tag`, `push --tags` | Restricts release tagging to human maintainers. |
| **`git`** | `rebase -i`, `--interactive`, `squash`, `fixup`, `--autosquash` | Prevents destructive history rewriting and obfuscating change history. |
| **`git`** | `merge --squash`, force-push (`-f`, `--force`, `--force-with-lease`) | Prohibits destructive overwrites on remote branches. |
| **`gh`** | `release` | Restricts release publication to human developers. |
| **`gh`** | `repo delete` | Prevents catastrophic repository deletion. |
| **`gh`** | `secret` | Prevents exposure or automated modification of repository/organization secrets. |
| **`gh`** | `issue comment`, `pr comment`, `pr review`, `-c`, `--comment` | Prevents agents from impersonating human developers in discussions or approvals. Feedback and drafts must be presented in chat. |
| **`gh`** | `pr merge`, `pr close`, `issue close`; mutating `api` (`/comments`, `/reviews`, `state=closed`) | Enforces human control over PR and issue lifecycles (issues close via merged PRs). |
| **`npm` / `npx`** | `--legacy-peer-deps`, `NPM_CONFIG_LEGACY_PEER_DEPS` | Prevents dirty dependency resolution bypasses; requires fixing root dependency conflicts. |
| **Data Layer** | Modifying `overwrite: false` to `true`, destructive storage class / volume changes | Protects database persistence layers and prevents accidental volume purging. |
| **Pipelines** | Modifying CI/CD deploy matrices, orchestrator flags, or safety toggles during bugfixes | Enforces Stateful Isolation Invariant: confine component fixes to component manifests. |

### Enforcement Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AI Agent Execution                            │
├──────────────────────────────────┬──────────────────────────────────────┤
│ Application / Prompt Layer       │ config/instructions.md               │
│                                  │ • Injected into Antigravity & Cursor │
│                                  │ • Prompt-Scope Fencing               │
│                                  │ • Hard Stop behavioral rules         │
├──────────────────────────────────┼──────────────────────────────────────┤
│ Global Git Hooks Layer           │ config/hooks/pre-commit (~/.githooks)│
│                                  │ • Gitleaks secret scanning           │
├──────────────────────────────────┼──────────────────────────────────────┤
│ Shell & Environment Layer        │ config/bashrc                        │
│                                  │ • Agent marker detection             │
│                                  │ • Clean non-interactive subshells    │
│                                  │ • Token isolation (GH_TOKEN unsets)  │
└──────────────────────────────────┴──────────────────────────────────────┘
```

1. **Global Git Pre-Commit Hook (`~/.githooks/pre-commit`)**: Configured globally via `git config --global core.hooksPath ~/.githooks`. Executes `gitleaks protect --staged --redact --no-banner` on every commit.
2. **Prompt-Scope Fencing & Behavioral Instructions (`config/instructions.md`)**: Injected into `~/.gemini/GEMINI.md` and Cursor global instructions to enforce operational discipline, fail-fast mechanics, inspect-before-verify, and immutable data safety rules.
3. **Shell & Agent Environment Isolation (`config/bashrc`)**: Copied to `~/.config/dotfiles/bashrc` on setup (not sourced from the git work tree). Detects AI agent execution (`ANTIGRAVITY_AGENT`) to strip prompt evaluation overhead and unset ambient `GITHUB_TOKEN` / `GH_TOKEN` environment variables so commands use authenticated local credentials.

### Bypassing (Human Developers Only)

* **Override Git Aliases / Wrappers**: Use the shell `command` builtin:
  ```bash
  command git config --local user.email "developer@example.com"
  ```
* **Bypass Git Hooks (Emergency Only)**:
  ```bash
  git commit --no-verify -m "fix: emergency out-of-band hotfix"
  ```

## Supply Chain & Trust Model

This repo's job is downloading and executing third-party software, and
`dotfiles-update.service` does it unattended at graphical login. That makes the
upstreams below part of the trusted computing base: compromise any one of them
and you get code execution on this machine at next login. What is verifiable is
verified; the rest is documented here rather than left implicit.

| Component | Integrity check | Notes |
| --- | --- | --- |
| `oc` | **sha256 verified** | Red Hat publishes `sha256sum.txt` per release; a mismatch aborts the install. |
| `jq`, `gh`, `gitleaks`, `docker-compose`, `shellcheck`, `actionlint`, `uv` | TLS only | GitHub release assets, resolved from the `/releases/latest` redirect. No upstream checksums. Archives are rejected if their members are absolute, traversing, or link outside the extraction directory. |
| Cursor AppImage | TLS + URL anchored | The download URL comes from Cursor's API and must sit under `https://downloads.cursor.com/`. |
| Antigravity hub | TLS + URL anchored | URL scraped from the download page, must be under `storage.googleapis.com/antigravity-public/`; archive checked for path traversal. |
| Insync | TLS + URL anchored + digest | URL anchored to `cdn.insynchq.com`. **Insync ships unsigned RPMs** (no `SIGPGP`/`RSAHEADER`), so there is nothing to verify against a key. `rpmkeys --checksig` confirms the package's own digests, and the installed hash is recorded to `~/.local/share/dotfiles/insync.sha256`. |
| `agy` CLI | TLS only | `curl \| bash` of `antigravity.google/cli/install.sh`. Upstream publishes no versioned installer or checksum. |
| `nvm` | Pinned tag | Installer fetched at a resolved release tag, not `main`. |
| Ponytail agent rule | Pinned commit | Pinned by SHA in `dev.sh`, since it becomes standing instructions for every agent session. Bump deliberately after reading the diff. |

Two other deliberate trade-offs:

* **Cursor runs with `--no-sandbox`**, because the AppImage can't use Chromium's
  sandbox without unprivileged userns. This gives up renderer isolation; drop
  the flag if a future build works without it.
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
│   ├── skills/
│   │   ├── podman-runner/             # Containerized execution & resource limits
│   │   └── typescript-standards/      # Modular agent skills
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
│   │   └── dev.sh                     # Toolchains (jq, gh, uv, nvm; `--tools` for CLIs only), AI assistants, oc & repos
│   ├── lib.sh                         # Shared helpers: output, install_copy, download guards
│   ├── updown.sh                      # Workstation updater script (installed to ~/.local/bin/updown)
│   ├── clone-repos.sh                 # Idempotent repository cloner
│   ├── tpm-enroll.sh                  # Optional TPM2 disk unlock helper (see Supply Chain below)
│   ├── update-antigravity.sh          # Runtime updater for Antigravity Hub
│   └── git-setup.sh                   # Interactive git config & signing helper
```
