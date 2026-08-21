#!/usr/bin/env bash
# updown — Workstation silent maintenance
# Stages rpm-ostree upgrade, updates flatpaks, updates third-party binaries,
# and updates Antigravity CLI + hub.
#
# Usage:
#   updown                 — run updates then power off (default / interactive)
#   updown --background, -b — run updates in the background without power off
#
# The systemd user service (config/systemd/dotfiles-update.service) calls
# this script with --background on graphical session start (at most once per 23h).

set -euo pipefail

SHUTDOWN=1
INSTALL_INSYNC=0

for arg in "$@"; do
    case "$arg" in
        --background|-b|--no-shutdown|-n)
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
            echo "  --background, -b     Run updates in background without power off"
            echo "  --install-insync     Bootstrap/update Insync only without power off"
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
fi

# ── 5. Insync ────────────────────────────────────────────────────────────────

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
                        chmod +x "$INSYNC_LIB_DIR/insync"
                        
                        # Extract application and status icons from RPM
                        extracted_icons="$(find "$tmp_dir" -type d -path "*/usr/share/icons" | head -n 1 || true)"
                        if [[ -n "$extracted_icons" && -d "$extracted_icons" ]]; then
                            mkdir -p "${HOME}/.local/share/icons" "${HOME}/.icons"
                            cp -rf "$extracted_icons/"* "${HOME}/.local/share/icons/"
                            [[ -f "/usr/share/icons/hicolor/index.theme" ]] && cp -f "/usr/share/icons/hicolor/index.theme" "${HOME}/.local/share/icons/hicolor/index.theme"
                            python3 - << 'PY'
import os
try:
    from PIL import Image
except ImportError:
    import sys
    sys.exit(0)

src_dir = os.path.expanduser("~/.local/share/icons/hicolor/48x48/status")
sizes = [16, 22, 24, 32, 48, 64, 128, 256]
icons = ["insync-alert", "insync-normal", "insync-offline", "insync-paused", "insync-synced", "insync-syncing"]

for icon in icons:
    src_file = os.path.join(src_dir, f"{icon}.png")
    if not os.path.exists(src_file):
        continue
    img = Image.open(src_file)
    for sz in sizes:
        dest_dir = os.path.expanduser(f"~/.local/share/icons/hicolor/{sz}x{sz}/status")
        os.makedirs(dest_dir, exist_ok=True)
        dest_file = os.path.join(dest_dir, f"{icon}.png")
        resized = img.resize((sz, sz), Image.LANCZOS)
        resized.save(dest_file, "PNG")
        for theme in ("breeze", "breeze-dark"):
            bdir = os.path.expanduser(f"~/.local/share/icons/{theme}/status/{sz}")
            os.makedirs(bdir, exist_ok=True)
            resized.save(os.path.join(bdir, f"{icon}.png"), "PNG")
PY
                            if command -v gtk-update-icon-cache &>/dev/null; then
                                gtk-update-icon-cache -f -q "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
                            fi
                        fi

                        cat > "$INSYNC_BIN" << 'EOF'
#!/bin/bash
export LC_TIME=C
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export XDG_DATA_DIRS="$HOME/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

if command -v bwrap &>/dev/null && [[ -d "$HOME/.local/share/icons/hicolor" ]]; then
    exec bwrap --dev-bind / / --bind "$HOME/.local/share/icons/hicolor" /usr/share/icons/hicolor "$HOME/.local/lib/insync/insync" "$@" || exec "$HOME/.local/lib/insync/insync" "$@"
else
    exec "$HOME/.local/lib/insync/insync" "$@"
fi
EOF
                        chmod +x "$INSYNC_BIN"
                        mkdir -p "$(dirname "$STAMP_FILE")"
                        echo "$LATEST_INSYNC_URL" > "$STAMP_FILE"
                        success "Insync updated"
                    else
                        warn "Insync copy failed — restoring previous installation"
                        rm -rf "$INSYNC_LIB_DIR"
                        [[ -d "${INSYNC_LIB_DIR}.old" ]] && mv "${INSYNC_LIB_DIR}.old" "$INSYNC_LIB_DIR"
                    fi
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
    # ── 6. Cursor ────────────────────────────────────────────────────────────────

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

    # ── 7. Standalone Dev CLI Tools ──────────────────────────────────────────────
    if [[ -f "$DOTFILES_DIR/scripts/setup/dev.sh" ]]; then
        info "Checking standalone CLI tools for updates..."
        UPDATE=1 bash "$DOTFILES_DIR/scripts/setup/dev.sh" --tools || warn "CLI tools update encountered warnings"
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
