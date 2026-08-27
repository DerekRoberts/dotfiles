#!/usr/bin/env bash
# updown — Workstation silent maintenance
# Stages rpm-ostree upgrade, updates flatpaks, updates third-party binaries,
# and updates Antigravity CLI + hub, Kilo CLI, and Cursor.
#
# Usage:
#   updown                 — run updates then power off (default / interactive)
#   updown --background, -b — run updates in the background without power off
#
# The systemd user service (config/systemd/dotfiles-update.service) calls
# this script with --background on graphical session start (at most once per 23h).

set -euo pipefail

SHUTDOWN=1

for arg in "$@"; do
    case "$arg" in
        --background|-b|--no-shutdown|-n)
            SHUTDOWN=0
            ;;
        --shutdown|-s)
            SHUTDOWN=1
            ;;
        --help|-h)
            echo "Usage: updown [options]"
            echo "  (default)            Run updates and power off"
            echo "  --background, -b     Run updates in background without power off"
            echo "  --help, -h           Show this help"
            exit 0
            ;;
    esac
done

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
if [[ -n "$SCRIPT_PATH" && -f "$(dirname "$SCRIPT_PATH")/../setup.sh" ]]; then
    DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
else
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Repos/dotfiles}"
fi
# Locate helper scripts in the clone. Never git-pull this repository from the
# updater: a remote change would become an execution path at login.
DOTFILES_PROFILE="${DOTFILES_PROFILE:-dev}"

# systemd user units often omit ~/.local/bin (where jq, gh, oc live)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# updown is installed to ~/.local/bin, so the clone it came from may be gone.
if [[ ! -f "$DOTFILES_DIR/scripts/lib.sh" ]]; then
    echo "[updown] ⚠ Cannot find $DOTFILES_DIR/scripts/lib.sh — set DOTFILES_DIR to the clone." >&2
    exit 1
fi
# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# This runs unattended from a systemd user unit, so prefix every line to make
# the journal readable.
info()    { echo "[updown] $*"; }
success() { echo "[updown] ✓ $*"; }
warn()    { echo "[updown] ⚠ $*" >&2; }

# ── 1. rpm-ostree ────────────────────────────────────────────────────────────
    # Stages the update; does NOT reboot automatically.
    # On Kinoite, apply takes effect on next reboot (user-controlled).

    info "Staging rpm-ostree upgrade..."
    if rpm-ostree upgrade --quiet 2>&1; then
        success "rpm-ostree upgrade staged (reboot when ready to apply)"
    else
        warn "rpm-ostree upgrade failed or nothing to do — continuing"
    fi

    # ── 2. Flatpak ───────────────────────────────────────────────────────────────

    info "Updating Flatpaks..."
    if flatpak update --user -y --noninteractive 2>&1; then
        success "User Flatpaks updated"
    else
        warn "Flatpak user update failed — continuing"
    fi
    if flatpak update --system -y --noninteractive 2>&1; then
        success "System Flatpaks updated"
    else
        # Not fatal if user is not in wheel or polkit denies silent system update
        info "System Flatpak update skipped or completed"
    fi

    # ── 3. Antigravity Hub ───────────────────────────────────────────────────────

    ANTI_UPDATER=""
    if command -v update-antigravity &>/dev/null; then
        ANTI_UPDATER="update-antigravity"
    elif [[ -x "$HOME/.local/bin/update-antigravity" ]]; then
        ANTI_UPDATER="$HOME/.local/bin/update-antigravity"
    elif [[ -f "$DOTFILES_DIR/scripts/update-antigravity.sh" ]]; then
        ANTI_UPDATER="$DOTFILES_DIR/scripts/update-antigravity.sh"
    fi

    if [[ -n "$ANTI_UPDATER" ]]; then
        bash "$ANTI_UPDATER" || warn "Antigravity hub update exited with error"
    else
        info "update-antigravity not found — skipping"
    fi


    # ── 4. agy CLI ───────────────────────────────────────────────────────────────
    # agy has its own update mechanism: agy update (or re-running the install script)

    AGY_BIN="${HOME}/.local/bin/agy"
    if [[ -x "$AGY_BIN" ]]; then
        info "Checking agy CLI for updates..."
        LATEST_AGY_VER=$(curl -fsSL https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json | jq -r .version 2>/dev/null || echo "unknown")
        CURRENT_AGY_VER=$("$AGY_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "none")

        if [[ "$LATEST_AGY_VER" != "unknown" ]] && [[ "$CURRENT_AGY_VER" == "$LATEST_AGY_VER" ]]; then
            success "agy CLI is up to date ($CURRENT_AGY_VER)"
        else
            info "Updating agy CLI ($CURRENT_AGY_VER -> $LATEST_AGY_VER)..."
            if curl -fsSL https://antigravity.google/cli/install.sh | bash 2>&1; then
                success "agy CLI updated"
            else
                warn "agy update failed — continuing"
            fi
        fi
    else
        info "agy CLI not installed — skipping"
    fi


    # ── 5. Kilo Code CLI (nvm npm global) ────────────────────────────────────
    if load_nvm && kilo_cli_installed; then
        info "Updating Kilo CLI..."
        if install_kilo_cli_pkg 2>&1; then
            success "Kilo CLI updated ($(kilo --version 2>/dev/null || echo ok))"
        else
            warn "Kilo CLI update failed — continuing"
        fi
    else
        info "Kilo CLI not installed — skipping"
    fi


    # ── 6. Cursor ────────────────────────────────────────────────────────────────

    CURSOR_BIN="${HOME}/.local/bin/cursor.AppImage"
    if [[ -x "$CURSOR_BIN" ]]; then
        info "Checking Cursor for updates..."
        LATEST_CURSOR_URL="$(cursor_latest_url || true)"

        STAMP_FILE="${HOME}/.local/share/dotfiles/cursor.url"
        if [[ -n "$LATEST_CURSOR_URL" ]]; then
            if [[ -f "$STAMP_FILE" ]] && [[ -x "$CURSOR_BIN" ]] && [[ "$(cat "$STAMP_FILE")" == "$LATEST_CURSOR_URL" ]]; then
                success "Cursor is up to date"
            else
                info "Updating Cursor..."
                if curl -L -fsS "$LATEST_CURSOR_URL" -o "${CURSOR_BIN}.tmp"; then
                    mv "${CURSOR_BIN}.tmp" "$CURSOR_BIN"
                    chmod +x "$CURSOR_BIN"
                    mkdir -p "$(dirname "$STAMP_FILE")"
                    echo "$LATEST_CURSOR_URL" > "$STAMP_FILE"
                    success "Cursor updated"
                else
                    warn "Cursor update failed (download error)"
                    rm -f "${CURSOR_BIN}.tmp"
                fi
            fi
        else
            warn "Cursor URL missing or outside $CURSOR_URL_PREFIX — skipping update"
        fi
    else
        info "Cursor not installed — skipping"
    fi

    # ── 7. Standalone Dev CLI Tools (includes oc) ───────────────────────────────
    if [[ -f "$DOTFILES_DIR/scripts/setup/dev.sh" ]]; then
        info "Checking standalone CLI tools for updates..."
        UPDATE=1 bash "$DOTFILES_DIR/scripts/setup/dev.sh" --tools || warn "CLI tools update encountered warnings"
    fi


# ── 8. SELinux context fix ───────────────────────────────────────────────────
# restorecon is always present on Kinoite (part of the base image).
# Fixes SELinux labels on any extracted binaries in ~/.local/bin.

info "Restoring SELinux contexts on ~/.local/bin..."
if command -v restorecon &>/dev/null; then
    restorecon -R "${HOME}/.local/bin" 2>&1 | grep -v "^$" || true
    success "SELinux contexts restored"
else
    info "restorecon not available — skipping (not on SELinux system?)"
fi

# ── 9. Shutdown ──────────────────────────────────────────────────────────────

echo ""
echo "✅ Maintenance complete."

if [[ "$SHUTDOWN" -eq 1 ]]; then
    echo "Shutting down system in 3 seconds (Ctrl+C to cancel)..."
    sleep 3
    systemctl poweroff
fi
