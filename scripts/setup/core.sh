#!/usr/bin/env bash
# core.sh — Core system, shell, and userspace wiring
#
# Usage:
#   scripts/setup/core.sh [--dev|--desktop]
#   scripts/setup/core.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASHRC="$HOME/.bashrc"
# Installed copies — never source or include the git work tree at runtime.
DOTFILES_USER_CONFIG="${DOTFILES_USER_CONFIG:-$HOME/.config/dotfiles}"

# ── Helpers ──────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# Git aliases that start with ! run a shell. The installed gitconfig copy is
# an execution surface; keep aliases as git builtins only.

# ── Shell Wiring ─────────────────────────────────────────────────────────────

wire_bashrc() {
    section "Shell Profile Wiring"

    local installed_bashrc="$DOTFILES_USER_CONFIG/bashrc"
    if [[ -f "$DOTFILES_DIR/config/bashrc" ]]; then
        install_copy "$DOTFILES_DIR/config/bashrc" "$installed_bashrc" 644
        success "Installed $installed_bashrc"
    fi

    if [[ -f "$BASHRC" && -f "$installed_bashrc" ]]; then
        info "Updating ~/.bashrc sourcing..."
        # Keep the pre-dotfiles original only. Re-running must not accumulate
        # backups of a file this script itself wrote.
        if [[ ! -f "$BASHRC.orig" ]]; then
            cp "$BASHRC" "$BASHRC.orig"
        fi

        # Filter broken Fedora gnupg2 profile.d tty warning during /etc/bashrc sourcing in flatpak/subshells
        sed -i -e '/tty: ttyname error/! s|\. /etc/bashrc|. /etc/bashrc 2> >(grep -v '"'"'tty: ttyname error'"'"' >\&2)|' "$BASHRC"
        
        # Drop our own loader before re-appending it
        sed -i '/Source personal dotfiles configuration/d; /if \[ -f.*bashrc.*\]; then/d; /\. .*bashrc/d; /fi/d' "$BASHRC"
        
        printf '\n# Source personal dotfiles configuration\nif [ -f "%s" ]; then\n    . "%s"\nfi\n' "$installed_bashrc" "$installed_bashrc" >> "$BASHRC"
        success "bashrc sourcing updated"
    fi

    # Ensure ~/.bash_profile forwards to ~/.bashrc for login shells
    local BASH_PROFILE="$HOME/.bash_profile"
    if [[ -f "$BASH_PROFILE" ]]; then
        # shellcheck disable=SC2016
        if ! grep -q '\. ~/.bashrc' "$BASH_PROFILE" && \
           ! grep -q 'source ~/.bashrc' "$BASH_PROFILE" && \
           ! grep -Fq '. "$HOME/.bashrc"' "$BASH_PROFILE" && \
           ! grep -Fq 'source "$HOME/.bashrc"' "$BASH_PROFILE" && \
           ! grep -Fq '. "${HOME}/.bashrc"' "$BASH_PROFILE" && \
           ! grep -Fq 'source "${HOME}/.bashrc"' "$BASH_PROFILE"; then
            info "Wiring ~/.bash_profile to source ~/.bashrc..."
            # shellcheck disable=SC2016
            printf '\nif [ -f "$HOME/.bashrc" ]; then\n    . "$HOME/.bashrc"\nfi\n' >> "$BASH_PROFILE"
            success "bash_profile sourcing wired"
        fi
    fi
}

# ── Maintenance Tools & Systemd Units ────────────────────────────────────────

install_maintenance_tools() {
    section "Maintenance Tools & Services"

    info "Installing maintenance scripts to ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    if [[ -f "$DOTFILES_DIR/scripts/updown.sh" ]]; then
        install_copy "$DOTFILES_DIR/scripts/updown.sh" "$HOME/.local/bin/updown"
        success "Installed updown → $HOME/.local/bin/updown"
    fi

    if [[ -d "$DOTFILES_DIR/config/systemd" ]]; then
        info "Configuring systemd user services..."
        local SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SYSTEMD_USER_DIR"
        for unit in "$DOTFILES_DIR/config/systemd"/*; do
            [[ -f "$unit" ]] || continue
            install_copy "$unit" "$SYSTEMD_USER_DIR/$(basename "$unit")" 644
        done
        if command -v systemctl &>/dev/null; then
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            if [[ -f "$DOTFILES_DIR/config/systemd/dotfiles-update.service" ]]; then
                systemctl --user enable dotfiles-update.service >/dev/null 2>&1 || true
            fi
            if [[ -f "$DOTFILES_DIR/config/systemd/kio-trash-sync.path" ]]; then
                systemctl --user enable --now kio-trash-sync.path >/dev/null 2>&1 || true
            fi
        fi
        success "systemd user units installed & enabled"
    fi
}

# ── User Directories & Dolphin Places ────────────────────────────────────────

configure_user_dirs() {
    local PROFILE="${1:-dev}"
    section "XDG User Directories & Places"

    local CONFIG_FILE="$HOME/.config/user-dirs.dirs"
    info "Writing strict XDG directory definitions..."

    mkdir -p "$HOME/.config"
    cat > "$CONFIG_FILE" << EOF
XDG_DESKTOP_DIR="\$HOME/Downloads"
XDG_DOCUMENTS_DIR="\$HOME/Documents"
XDG_DOWNLOAD_DIR="\$HOME/Downloads"
XDG_MUSIC_DIR="\$HOME/Documents"
XDG_PICTURES_DIR="\$HOME/Documents"
XDG_PROJECTS_DIR="\$HOME/Documents"
XDG_PUBLICSHARE_DIR="\$HOME/Documents"
XDG_TEMPLATES_DIR="\$HOME/Documents"
XDG_VIDEOS_DIR="\$HOME/Documents"
EOF

    # Prevent xdg-user-dirs-update from recreating default folders
    echo "enabled=False" > "$HOME/.config/user-dirs.conf"

    info "Cleaning up unused default directories (if empty)..."
    for dir in Desktop Music Pictures Public Templates Videos; do
        if [[ -d "$HOME/$dir" ]]; then
            local non_meta_files
            non_meta_files="$(find "$HOME/$dir" -mindepth 1 -maxdepth 1 ! -name ".directory" 2>/dev/null)"
            if [[ -z "$non_meta_files" ]]; then
                rm -rf "${HOME:?}/${dir:?}"
            fi
        fi
    done

    # Ensure Downloads explicitly defines the folder-downloads icon metadata
    if [[ -d "$HOME/Downloads" ]]; then
        echo -e "[Desktop Entry]\nIcon=folder-downloads\nType=Directory" > "$HOME/Downloads/.directory"
    fi

    info "Configuring Dolphin sidebar places..."
    if [[ -f "$DOTFILES_DIR/config/kde/user-places.xbel" ]]; then
        mkdir -p "$HOME/.local/share"
        if [[ "$PROFILE" == "desktop" && ! -d "$HOME/Repos" ]]; then
            sed -e "s|/var/home/derek|$HOME|g" -e '/<title>Repos<\/title>/d' "$DOTFILES_DIR/config/kde/user-places.xbel" > "$HOME/.local/share/user-places.xbel"
        else
            sed "s|/var/home/derek|$HOME|g" "$DOTFILES_DIR/config/kde/user-places.xbel" > "$HOME/.local/share/user-places.xbel"
        fi
        success "Dolphin sidebar configured"
    fi

    # Invalidate and rebuild KDE system configuration cache for XDG user directories
    rebuild_ksycoca
    info "KDE sycoca cache rebuilt"
}

# ── Application MIME Defaults & Spectacle ────────────────────────────────────

configure_mime_defaults() {
    section "Default Applications & File Associations"

    info "Configuring default application associations..."
    
    local chrome="com.google.Chrome.desktop"
    local gwenview="org.kde.gwenview.desktop"
    local vlc="org.videolan.VLC.desktop"
    local ark="org.kde.ark.desktop"
    
    for mime in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml x-scheme-handler/mailto text/calendar x-scheme-handler/tel application/pdf; do
        xdg-mime default "$chrome" "$mime" 2>/dev/null || true
    done
    
    for mime in image/jpeg image/png image/gif image/webp image/bmp image/svg+xml image/tiff image/avif; do
        xdg-mime default "$gwenview" "$mime" 2>/dev/null || true
    done
    
    for mime in audio/mpeg audio/mp3 audio/mp4 audio/flac audio/ogg audio/x-wav audio/wav audio/aac audio/x-vorbis+ogg audio/x-opus+ogg video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/mpeg video/ogg video/x-flv; do
        xdg-mime default "$vlc" "$mime" 2>/dev/null || true
    done
    
    for mime in application/zip application/x-tar application/x-7z-compressed application/x-compressed-tar application/x-bzip-compressed-tar application/x-xz-compressed-tar application/x-rar; do
        xdg-mime default "$ark" "$mime" 2>/dev/null || true
    done
    
    xdg-mime default "org.kde.kwrite.desktop" "text/plain" 2>/dev/null || true
    xdg-mime default "org.kde.dolphin.desktop" "inode/directory" 2>/dev/null || true
    xdg-mime default "openstreetmap-geo-handler.desktop" "x-scheme-handler/geo" 2>/dev/null || true
    xdg-mime default "antigravity.desktop" "x-scheme-handler/antigravity" 2>/dev/null || true
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kdeglobals --group General --key TerminalApplication org.kde.konsole.desktop
        kwriteconfig6 --file kdeglobals --group General --key TerminalService org.kde.konsole.desktop
        kwriteconfig6 --file kdeglobals --group KDE --key DndBehavior MoveIfSameDevice
    fi
    success "Default applications and drag-and-drop behavior configured"

    if command -v kwriteconfig6 &>/dev/null; then
        info "Configuring Spectacle save locations to ~/Downloads..."
        local key
        for key in imageSaveLocation lastImageSaveLocation lastImageSaveAsLocation; do
            kwriteconfig6 --file spectaclerc --group ImageSave --key "$key" "file://$HOME/Downloads"
        done
        for key in videoSaveLocation lastVideoSaveLocation lastVideoSaveAsLocation; do
            kwriteconfig6 --file spectaclerc --group VideoSave --key "$key" "file://$HOME/Downloads"
        done
        success "Spectacle configured to save screenshots and recordings to ~/Downloads"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
Usage:
  scripts/setup/core.sh [OPTIONS]

Options:
  --dev       Apply dev profile directory and places wiring (default)
  --desktop   Apply desktop profile directory wiring
  --help, -h  Show this help
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
        --dev|"")
            PROFILE="dev"
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac

    echo "=== Configuring Core System & Shell ($PROFILE profile) ==="
    wire_bashrc
    install_maintenance_tools
    configure_user_dirs "$PROFILE"
    configure_mime_defaults
    success "Core configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
