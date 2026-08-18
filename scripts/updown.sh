#!/usr/bin/env bash
# updown — Workstation silent maintenance
# Stages rpm-ostree upgrade, updates flatpaks, updates third-party binaries,
# and updates Antigravity CLI + hub.
#
# Usage:
#   updown                   — run updates then power off (default / interactive)
#   updown --no-shutdown, -n — run updates without powering off (background / CI)
#
# The systemd user service (config/systemd/dotfiles-update.service) calls
# this script with --no-shutdown on graphical session start (at most once per 23h).

set -euo pipefail

SHUTDOWN=1
INSTALL_INSYNC=0

for arg in "$@"; do
    case "$arg" in
        --no-shutdown|--background|-n)
            SHUTDOWN=0
            ;;
        --install-insync)
            INSTALL_INSYNC=1
            SHUTDOWN=0
            ;;
        --shutdown|-s)
            SHUTDOWN=1
            ;;
        --help|-h)
            echo "Usage: updown [options]"
            echo "  (default)            Run updates and power off"
            echo "  --no-shutdown, -n    Run updates without powering off"
            echo "  --install-insync     Bootstrap/update Insync only without shutdown"
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
DOTFILES_PROFILE="${DOTFILES_PROFILE:-dev}"
LOG_PREFIX="[updown]"

info()    { echo "$LOG_PREFIX $*"; }
success() { echo "$LOG_PREFIX ✓ $*"; }
warn()    { echo "$LOG_PREFIX ⚠ $*" >&2; }

if [[ "$INSTALL_INSYNC" -eq 0 ]]; then
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

    # ── 4. Antigravity Hub ───────────────────────────────────────────────────────

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


    # ── 5. agy CLI ───────────────────────────────────────────────────────────────
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
fi

# ── 6. Insync ────────────────────────────────────────────────────────────────

INSYNC_BIN="${HOME}/.local/bin/insync"
INSYNC_LIB_DIR="${HOME}/.local/lib/insync"
if [[ -x "$INSYNC_BIN" ]] || [[ "$INSTALL_INSYNC" -eq 1 ]]; then
    info "Checking Insync for updates..."
    INSYNC_JS_URL="https://cdn.insynchq.com/web/webflow/js/linux_download_links.js"
    LATEST_INSYNC_URL="$(curl -fsSL "$INSYNC_JS_URL" | grep -oE 'https://cdn\.insynchq\.com/builds/linux/[^"]+\.x86_64\.rpm' | grep -v 'headless' | grep 'fc44' | head -n 1 || true)"
    if [[ -z "$LATEST_INSYNC_URL" ]]; then
        LATEST_INSYNC_URL="$(curl -fsSL "$INSYNC_JS_URL" | grep -oE 'https://cdn\.insynchq\.com/builds/linux/[^"]+\.x86_64\.rpm' | grep -v 'headless' | grep -E 'fc[0-9]+' | sort -t'c' -k2 -rn | head -n 1 || true)"
    fi

    STAMP_FILE="${HOME}/.local/share/dotfiles/insync.url"
    if [[ -n "$LATEST_INSYNC_URL" ]]; then
        if [[ -f "$STAMP_FILE" ]] && [[ -x "$INSYNC_LIB_DIR/insync" ]] && [[ "$(cat "$STAMP_FILE")" == "$LATEST_INSYNC_URL" ]]; then
            success "Insync is up to date"
        else
            info "Updating Insync..."
            tmp_dir="$(mktemp -d)"
            if curl -fsSL "$LATEST_INSYNC_URL" -o "$tmp_dir/insync.rpm" && \
               (cd "$tmp_dir" && rpm2cpio insync.rpm | cpio -idm 2>/dev/null); then
                extracted_lib="$(find "$tmp_dir" -type d -path "*/usr/lib/insync" | head -n 1 || true)"
                if [[ -n "$extracted_lib" && -f "$extracted_lib/insync" ]]; then
                    mkdir -p "${HOME}/.local/lib" "${HOME}/.local/bin"
                    rm -rf "${INSYNC_LIB_DIR}.old"
                    [[ -d "$INSYNC_LIB_DIR" ]] && mv "$INSYNC_LIB_DIR" "${INSYNC_LIB_DIR}.old"
                    if cp -rf "$extracted_lib" "$INSYNC_LIB_DIR"; then
                        rm -rf "${INSYNC_LIB_DIR}.old"
                    else
                        warn "Insync copy failed — restoring previous installation"
                        [[ -d "${INSYNC_LIB_DIR}.old" ]] && mv "${INSYNC_LIB_DIR}.old" "$INSYNC_LIB_DIR"
                        rm -rf "$tmp_dir"
                        continue
                    fi
                    chmod +x "$INSYNC_LIB_DIR/insync"
                    
                    cat > "$INSYNC_BIN" << 'EOF'
#!/bin/bash
LC_TIME=C exec "$HOME/.local/lib/insync/insync" "$@"
EOF
                    chmod +x "$INSYNC_BIN"
                    mkdir -p "$(dirname "$STAMP_FILE")"
                    echo "$LATEST_INSYNC_URL" > "$STAMP_FILE"
                    success "Insync updated"
                else
                    warn "Insync update failed (library bundle not found in RPM)"
                fi
            else
                warn "Insync update failed (download/extract error)"
            fi
            rm -rf "$tmp_dir"
        fi
    else
        warn "Could not resolve Insync URL — skipping update"
    fi
else
    info "Insync not installed — skipping"
fi

if [[ "$INSTALL_INSYNC" -eq 0 ]]; then
    # ── 7. Cursor ────────────────────────────────────────────────────────────────

    CURSOR_BIN="${HOME}/.local/bin/cursor.AppImage"
    if [[ -x "$CURSOR_BIN" ]]; then
        info "Checking Cursor for updates..."
        LATEST_CURSOR_URL="$(curl -fsSL 'https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable' | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4 || true)"
        
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
            warn "Could not resolve Cursor URL — skipping update"
        fi
    else
        info "Cursor not installed — skipping"
    fi
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
