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

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

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

        kwin_reconfigure
    else
        warn "kwriteconfig6 not found — cannot set global shortcut automatically."
    fi
}

# ── Standalone Applications ──────────────────────────────────────────────────

ensure_insync_repo() {
    if [[ -f /etc/yum.repos.d/insync.repo ]]; then
        return 0
    fi
    sudo curl -fsSL https://d2t3ff60b2tol4.cloudfront.net/repomd.xml.key -o /etc/pki/rpm-gpg/RPM-GPG-KEY-insync || true
    sudo bash -c "cat > /etc/yum.repos.d/insync.repo << 'EOF'
[insync]
name=insync repo
baseurl=http://yum.insync.io/fedora/\$releasever/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-insync
enabled=1
metadata_expire=120m
type=rpm-md
EOF"
}

install_insync() {
    section "Insync"
    local installed latest
    if rpm -q insync &>/dev/null; then
        installed="$(rpm -q --qf '%{VERSION}-%{RELEASE}' insync)"
        latest="$(insync_repo_evr || true)"
        if [[ -n "$latest" ]] && evr_older_than "$installed" "$latest"; then
            info "Updating Insync ($installed → $latest) via rpm-ostree..."
            ensure_insync_repo
            # Inherit the cached sudo credential so we don't pop a separate graphical polkit prompt
            sudo rpm-ostree uninstall insync --install insync || warn "Failed to update Insync"
            return
        fi
        success "Insync is layered via rpm-ostree ($installed)"
        return
    fi
    info "Installing Insync natively via rpm-ostree (will prompt for sudo)..."
    ensure_insync_repo
    sudo rpm-ostree install insync || warn "Failed to layer Insync"
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

    # Insync is the only step that needs root; skip the prompt unless we still
    # need to layer it or a newer RPM is in the yum repo.
    if insync_needs_root; then
        sudo -v
    fi

    echo "=== Installing Applications ($PROFILE profile) ==="
    install_chrome
    install_vlc
    if [[ "$PROFILE" == "dev" ]]; then
        install_yakuake
    fi
    install_insync
    rebuild_ksycoca
    success "Application installation complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
