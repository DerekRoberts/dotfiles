# GitHub Copilot Repository Instructions: Dotfiles

Repository-specific architectural rules and maintenance guidelines for [`DerekRoberts/dotfiles`](https://github.com/DerekRoberts/dotfiles).

---

## 1. Workstation App Placement Architecture (3-Tier Rule)

This repository configures **Fedora Kinoite** (an immutable, rpm-ostree-based KDE Plasma system). To maintain stability, update safety, and reproducibility, all software must adhere strictly to the **3-Tier Rule**:

### Tier 1: Core / Permanent Tools (Dotfiles Managed)
- **Scope:** Base desktop software, terminal utilities, shell environments, and essential editor configurations needed continuously across all contexts.
- **Placement & Mechanism:**
  - **Flatpaks:** User-level installs via `--user` Flathub (`flatpak install --user -y flathub <app-id>`) wired into `setup.sh`.
  - **Binaries / AppImages / Tarballs:** Extracted or downloaded into `~/.local/bin` and `~/.local/lib` without elevating permissions.
  - **Updater Integration:** Wired into `scripts/bootstrap-tools.sh` and `scripts/updown.sh` with process kill guards (`kill_running_apps`) and URL/hash stamp checks in `~/.local/share/dotfiles/*.url`.
- **Zero Host OS Layering:** Never use `rpm-ostree install` or mutate `/usr`. Host layering is strictly forbidden.

### Tier 2: Ephemeral Dev Tools / Compilers (Container Isolated)
- **Scope:** Compilers (gcc, clang, rustc), build dependencies, project-specific databases, containerized SDKs, and ephemeral debuggers.
- **Placement & Mechanism:**
  - Kept entirely **out of the dotfiles repository**.
  - Direct developers to containerized userspace environments using Distrobox or Toolbx (e.g., `toolbox enter dev` or `distrobox enter dev`).
  - The host system remains pristine; SDK churn is isolated inside containers.

### Tier 3: Runtimes & Toolchain Managers (User Environment Managed)
- **Scope:** Version managers and toolchain bootstrappers (`nvm`, `uv`, `cargo`).
- **Placement & Mechanism:**
  - Dotfiles only manages the toolchain managers themselves in user directories (e.g., `~/.nvm`, `~/.cargo/bin`).
  - Individual applications and projects must manage their own pinned dependencies and package trees (`node_modules`, virtual environments, etc.).

---

## 2. Kinoite Immutability & Testing Hygiene

- **Userspace Isolation:** All configuration, data, and binaries must reside strictly under `$HOME` (`~/.local`, `~/.config`, `~/.var`).
- **ShellCheck Compliance:** All modified or newly authored Bash scripts must pass ShellCheck without warnings or silenced errors (`shellcheck setup.sh scripts/*.sh scripts/setup/*.sh`).
- **Syntax Verification:** Ensure `bash -n setup.sh` and `bash -n scripts/*.sh scripts/setup/*.sh` validate cleanly.
- **Idempotency & Fail-Safe Execution:** Every script must be safe to execute multiple times (`set -euo pipefail`, presence checks before actions, atomic staging via `mktemp`).

---

## 3. Platform Expansion Guidance

When adapting scripts, installers, or configurations for other operating systems or environments:
- **Reference Tracking:** Consult and reference GitHub Issue #45 when designing or implementing support for macOS (Homebrew) or Windows (WSL).
- **Preserve Tier Boundaries:** Even on mutable OS platforms (macOS/Windows), maintain separation between core workstation utilities, ephemeral toolchains, and project dependencies.
