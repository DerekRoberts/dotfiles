#!/usr/bin/env bash
# apps.sh — Application installers (Flatpaks & standalone apps)
#
# Usage:
#   scripts/setup/apps.sh [--dev|--desktop|--all]
#   scripts/setup/apps.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# ── Flathub Remote ───────────────────────────────────────────────────────────

ensure_flathub() {
    if ! flatpak remote-list --user 2>/dev/null | grep -q "flathub"; then
        info "Adding Flathub remote..."
        flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
}

# ── Flatpak Applications ─────────────────────────────────────────────────────

install_chrome() {
    section "Google Chrome"
    if flatpak list --user 2>/dev/null | grep -q "com.google.Chrome"; then
        success "Chrome already installed (Flatpak)"
    else
        ensure_flathub
        info "Installing Chrome via Flatpak..."
        flatpak install --user -y flathub com.google.Chrome
        success "Chrome installed"
    fi

    info "Configuring Chrome autostart..."
    local AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/com.google.Chrome.desktop" << 'DESKTOP'
[Desktop Entry]
Name=Google Chrome
Exec=flatpak run com.google.Chrome
Type=Application
X-Flatpak=com.google.Chrome
DESKTOP
    success "Chrome added to autostart"
}

install_vlc() {
    section "VLC Media Player"
    if flatpak list --user 2>/dev/null | grep -q "org.videolan.VLC"; then
        success "VLC already installed (Flatpak)"
    else
        ensure_flathub
        info "Installing VLC via Flatpak..."
        flatpak install --user -y flathub org.videolan.VLC
        success "VLC installed"
    fi
}

install_yakuake() {
    section "Yakuake (Drop-down Terminal)"

    if flatpak list --user 2>/dev/null | grep -q "org.kde.yakuake"; then
        success "Yakuake already installed (Flatpak)"
    else
        ensure_flathub
        info "Installing Yakuake via Flatpak..."
        flatpak install --user -y flathub org.kde.yakuake
        success "Yakuake installed"
    fi

    info "Configuring Yakuake autostart..."
    local AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/org.kde.yakuake.desktop" << 'DESKTOP'
[Desktop Entry]
Categories=Qt;KDE;System;TerminalEmulator;
Comment=A drop-down terminal emulator based on KDE Konsole technology.
DBusActivatable=true
Exec=flatpak run org.kde.yakuake
GenericName=Drop-down Terminal
Icon=org.kde.yakuake
Name=Yakuake
StartupNotify=false
Terminal=false
Type=Application
X-Flatpak=org.kde.yakuake
DESKTOP

    info "Setting Yakuake toggle shortcut to Ctrl+Space and disabling tray icon..."
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kglobalshortcutsrc --group yakuake --key toggle-window-state "Ctrl+Space,F12,Open/Retract Yakuake"

        # Hide the system tray icon natively (Flatpak Yakuake config)
        local YAKUAKE_CONFIG="$HOME/.var/app/org.kde.yakuake/config/yakuakerc"
        mkdir -p "$(dirname "$YAKUAKE_CONFIG")"
        kwriteconfig6 --file "$YAKUAKE_CONFIG" --group Window --key ShowSystrayIcon false

        # Reload shortcuts / KWin in KDE Plasma 6
        if command -v qdbus-qt6 &>/dev/null; then
            qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        elif command -v qdbus6 &>/dev/null; then
            qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        elif command -v qdbus &>/dev/null; then
            qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        fi
    else
        warn "kwriteconfig6 not found — cannot set global shortcut automatically."
    fi
}

# ── Standalone Applications ──────────────────────────────────────────────────

install_insync() {
    section "Insync"
    # Insync has no Flatpak or AppImage. We download the RPM, extract the
    # binaries with rpm2cpio, and install to ~/.local — zero host mutation.
    local BIN_DIR="$HOME/.local/bin"
    local INSYNC_BIN="$BIN_DIR/insync"
    local APPS_DIR="$HOME/.local/share/applications"

    if [[ -x "$INSYNC_BIN" ]]; then
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
        success "Insync already installed (wrapper updated)"
        local AUTOSTART_DIR="$HOME/.config/autostart"
        mkdir -p "$AUTOSTART_DIR" "$APPS_DIR"
        if [[ -f "$APPS_DIR/insync.desktop" ]]; then
            grep -q "X-KDE-autostart-after=panel" "$APPS_DIR/insync.desktop" || printf '\nX-KDE-autostart-after=panel\nX-KDE-autostart-phase=2\n' >> "$APPS_DIR/insync.desktop"
            rm -f "$AUTOSTART_DIR/insync.desktop"
            cp -f "$APPS_DIR/insync.desktop" "$AUTOSTART_DIR/insync.desktop"
            success "Insync added to autostart"
        fi
        return
    fi

    info "Downloading/Updating Insync..."
    bash "$DOTFILES_DIR/scripts/updown.sh" --install-insync

    if [[ ! -x "$INSYNC_BIN" ]]; then
        warn "Insync installation failed"
        return 1
    fi

    # Desktop entry
    mkdir -p "$APPS_DIR"
    cat > "$APPS_DIR/insync.desktop" << 'DESKTOP'
[Desktop Entry]
Name=Insync
Comment=Google Drive, OneDrive, and Dropbox sync
Exec=%h/.local/bin/insync start
Icon=insync
Terminal=false
Type=Application
Categories=Network;FileTransfer;
StartupNotify=true
X-KDE-autostart-after=panel
X-KDE-autostart-phase=2
DESKTOP
    sed -i "s|%h|$HOME|g" "$APPS_DIR/insync.desktop"

    local AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    rm -f "$AUTOSTART_DIR/insync.desktop"
    cp -f "$APPS_DIR/insync.desktop" "$AUTOSTART_DIR/insync.desktop"

    success "Insync installed to $INSYNC_BIN and added to autostart"
    info "Run: insync start"
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
Usage:
  scripts/setup/apps.sh [OPTIONS]

Options:
  --dev, --all   Install full application suite: Chrome, VLC, Yakuake, Insync (default)
  --desktop      Install minimal desktop apps: Chrome, VLC, Insync
  --help, -h     Show this help
EOF
}

main() {
    local PROFILE="dev"
    case "${1:-}" in
        --help|-h)
            usage
            exit 0
            ;;
        --desktop)
            PROFILE="desktop"
            ;;
        --dev|--all|"")
            PROFILE="dev"
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac

    echo "=== Installing Applications ($PROFILE profile) ==="
    install_chrome
    install_vlc
    if [[ "$PROFILE" == "dev" ]]; then
        install_yakuake
    fi
    install_insync
    success "Application installation complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
