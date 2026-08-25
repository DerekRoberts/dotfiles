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
self_test_gitconfig_no_shell_aliases() {
    local gc="$DOTFILES_DIR/config/gitconfig"
    if [[ ! -f "$gc" ]]; then
        echo "FAIL: gitconfig missing: $gc" >&2
        return 1
    fi
    if grep -E '^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*!' "$gc"; then
        echo "FAIL: git alias must not shell out" >&2
        return 1
    fi
    echo "gitconfig alias self-test passed"
}

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

        python3 - "$BASHRC" "$installed_bashrc" << 'PY'
import sys, re
path, installed = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()

# Filter broken Fedora gnupg2 profile.d tty warning during /etc/bashrc sourcing in flatpak/subshells
content = re.sub(
    r"if \[ -f /etc/bashrc \]; then\n\s*\. /etc/bashrc(?:\s*2>.*)?\nfi",
    "if [ -f /etc/bashrc ]; then\n    . /etc/bashrc 2> >(grep -v 'tty: ttyname error' >&2)\nfi",
    content,
)

# Drop our own loader before re-appending it, so re-runs stay idempotent.
content = re.sub(
    r"# Source personal dotfiles configuration\nif \[ -f [\"']?[^\"'\n]+/(?:config/)?bashrc[\"']? \]; then\n    \. [\"']?[^\"'\n]+/(?:config/)?bashrc[\"']?\nfi\n*",
    "",
    content,
)

loader = (
    f"\n\n# Source personal dotfiles configuration\n"
    f'if [ -f "{installed}" ]; then\n'
    f'    . "{installed}"\n'
    f"fi\n"
)
with open(path, "w") as f:
    f.write(content.rstrip() + loader)
PY
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

    # Ensure Downloads explicitly defines the folder-downloads icon metadata without discarding existing view settings
    if [[ -d "$HOME/Downloads" ]]; then
        python3 - "$HOME/Downloads/.directory" << 'PY'
import sys, os, tempfile

path = sys.argv[1]
dir_path = os.path.dirname(path)

lines = []
if os.path.exists(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

new_lines = []
in_desktop_entry = False
has_desktop_entry = False
icon_set = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_desktop_entry and not icon_set:
            new_lines.append("Icon=folder-downloads\n")
            icon_set = True
        in_desktop_entry = (stripped == "[Desktop Entry]")
        if in_desktop_entry:
            has_desktop_entry = True
        new_lines.append(line)
        continue
    
    if in_desktop_entry:
        if stripped.startswith("Icon="):
            new_lines.append("Icon=folder-downloads\n")
            icon_set = True
            continue
    new_lines.append(line)

if not has_desktop_entry:
    if new_lines and not new_lines[-1].endswith("\n"):
        new_lines[-1] += "\n"
    new_lines.append("[Desktop Entry]\nIcon=folder-downloads\nType=Directory\n")
elif in_desktop_entry and not icon_set:
    new_lines.append("Icon=folder-downloads\n")

tmp_fd, tmp_path = tempfile.mkstemp(prefix=".directory.tmp.", dir=dir_path)
with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
    f.writelines(new_lines)
os.chmod(tmp_path, 0o644)
os.replace(tmp_path, path)
PY
    fi

    repair_icon_theme_pollution

    info "Configuring Dolphin sidebar places..."
    if [[ -f "$DOTFILES_DIR/config/kde/user-places.xbel" ]]; then
        mkdir -p "$HOME/.local/share"
        if [[ "$PROFILE" == "desktop" && ! -d "$HOME/Repos" ]]; then
            python3 - "$DOTFILES_DIR/config/kde/user-places.xbel" "$HOME/.local/share/user-places.xbel" "$HOME" << 'PY'
import sys, re

src, dst, home = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("/var/home/derek", home)
content = re.sub(r"\s*<bookmark href=\"file://[^\"]+/Repos\">\s*<title>Repos</title>[\s\S]*?</bookmark>\s*", "\n", content)

with open(dst, "w", encoding="utf-8") as f:
    f.write(content)
PY
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
    local MIMEAPPS="$HOME/.config/mimeapps.list"
    python3 - "$MIMEAPPS" << 'PY'
import sys, os, configparser

path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)

defaults = {
    # Internet
    "x-scheme-handler/http": "com.google.Chrome.desktop",
    "x-scheme-handler/https": "com.google.Chrome.desktop",
    "text/html": "com.google.Chrome.desktop",
    "application/xhtml+xml": "com.google.Chrome.desktop",
    "x-scheme-handler/mailto": "com.google.Chrome.desktop",
    "text/calendar": "com.google.Chrome.desktop",
    "x-scheme-handler/tel": "com.google.Chrome.desktop",
    # Multimedia
    "image/jpeg": "org.kde.gwenview.desktop",
    "image/png": "org.kde.gwenview.desktop",
    "image/gif": "org.kde.gwenview.desktop",
    "image/webp": "org.kde.gwenview.desktop",
    "image/bmp": "org.kde.gwenview.desktop",
    "image/svg+xml": "org.kde.gwenview.desktop",
    "image/tiff": "org.kde.gwenview.desktop",
    "image/avif": "org.kde.gwenview.desktop",
    "audio/mpeg": "org.videolan.VLC.desktop",
    "audio/mp3": "org.videolan.VLC.desktop",
    "audio/mp4": "org.videolan.VLC.desktop",
    "audio/flac": "org.videolan.VLC.desktop",
    "audio/ogg": "org.videolan.VLC.desktop",
    "audio/x-wav": "org.videolan.VLC.desktop",
    "audio/wav": "org.videolan.VLC.desktop",
    "audio/aac": "org.videolan.VLC.desktop",
    "audio/x-vorbis+ogg": "org.videolan.VLC.desktop",
    "audio/x-opus+ogg": "org.videolan.VLC.desktop",
    "video/mp4": "org.videolan.VLC.desktop",
    "video/x-matroska": "org.videolan.VLC.desktop",
    "video/webm": "org.videolan.VLC.desktop",
    "video/quicktime": "org.videolan.VLC.desktop",
    "video/x-msvideo": "org.videolan.VLC.desktop",
    "video/mpeg": "org.videolan.VLC.desktop",
    "video/ogg": "org.videolan.VLC.desktop",
    "video/x-flv": "org.videolan.VLC.desktop",
    # Documents
    "text/plain": "org.kde.kwrite.desktop",
    "application/pdf": "com.google.Chrome.desktop",
    # Utilities
    "inode/directory": "org.kde.dolphin.desktop",
    "application/zip": "org.kde.ark.desktop",
    "application/x-tar": "org.kde.ark.desktop",
    "application/x-7z-compressed": "org.kde.ark.desktop",
    "application/x-compressed-tar": "org.kde.ark.desktop",
    "application/x-bzip-compressed-tar": "org.kde.ark.desktop",
    "application/x-xz-compressed-tar": "org.kde.ark.desktop",
    "application/x-rar": "org.kde.ark.desktop",
    "x-scheme-handler/geo": "openstreetmap-geo-handler.desktop",
    "x-scheme-handler/antigravity": "antigravity.desktop",
}

config = configparser.RawConfigParser()
if os.path.exists(path):
    config.read(path)

for section in ("Default Applications", "Added Associations"):
    if not config.has_section(section):
        config.add_section(section)
    for mime, desktop in defaults.items():
        val = desktop if section == "Default Applications" else f"{desktop};"
        config.set(section, mime, val)

with open(path, "w") as f:
    config.write(f, space_around_delimiters=False)
PY
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
        --self-test)
            self_test_lib
            self_test_gitconfig_no_shell_aliases
            exit $?
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
