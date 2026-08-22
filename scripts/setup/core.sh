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

# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# Point dest at src. A real directory at dest must be removed first:
# ln -sfn would otherwise create dest/$(basename src) inside it.
link_into() {
    local src="$1" dest="$2"
    if [[ ! -e "$src" && ! -L "$src" ]]; then
        warn "link source missing: $src"
        return 1
    fi
    mkdir -p "$(dirname "$dest")"
    if [[ -d "$dest" && ! -L "$dest" ]]; then
        rm -rf "$dest"
    fi
    ln -sfn "$src" "$dest"
}

self_test_link_into() {
    local tmp src dest
    tmp="$(mktemp -d)"
    src="$tmp/src"
    dest="$tmp/dest"
    mkdir -p "$src" "$dest"
    echo live > "$src/updown.sh"
    echo stale > "$dest/updown.sh"
    link_into "$src/updown.sh" "$dest/updown.sh"
    [[ -L "$dest/updown.sh" ]] || { echo "FAIL: file was not replaced with a symlink" >&2; rm -rf "$tmp"; return 1; }
    [[ "$(cat "$dest/updown.sh")" == "live" ]] || { echo "FAIL: symlink did not follow source file" >&2; rm -rf "$tmp"; return 1; }

    mkdir -p "$src/hooks" "$dest/hooks"
    echo hook > "$src/hooks/pre-commit"
    echo copy > "$dest/hooks/pre-commit"
    link_into "$src/hooks" "$dest/hooks"
    [[ -L "$dest/hooks" ]] || { echo "FAIL: directory was not replaced with a symlink" >&2; rm -rf "$tmp"; return 1; }
    [[ "$(cat "$dest/hooks/pre-commit")" == "hook" ]] || { echo "FAIL: dir symlink did not follow source" >&2; rm -rf "$tmp"; return 1; }

    link_into "$src/hooks" "$dest/hooks"
    [[ -L "$dest/hooks" && "$(cat "$dest/hooks/pre-commit")" == "hook" ]] || { echo "FAIL: relink was not idempotent" >&2; rm -rf "$tmp"; return 1; }

    rm -rf "$tmp"
    echo "link_into self-test passed"
}

# ── Shell Wiring ─────────────────────────────────────────────────────────────

wire_bashrc() {
    section "Shell Profile Wiring"

    if [[ -f "$BASHRC" ]]; then
        info "Updating ~/.bashrc sourcing..."
        cp "$BASHRC" "$BASHRC.bak.$(date +%s)"

        python3 - "$BASHRC" "$DOTFILES_DIR" << 'PY'
import sys, re
path, repo_dir = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()

# Filter broken Fedora gnupg2 profile.d tty warning during /etc/bashrc sourcing in flatpak/subshells
content = re.sub(
    r"if \[ -f /etc/bashrc \]; then\n\s*\. /etc/bashrc(?:\s*2>.*)?\nfi",
    "if [ -f /etc/bashrc ]; then\n    . /etc/bashrc 2> >(grep -v 'tty: ttyname error' >&2)\nfi",
    content,
)

content = re.sub(r".*/Documents/1-Personal/Linux/bashrc.*\n*", "", content)
content = re.sub(
    r"# Source personal dotfiles configuration\nif \[ -f [\"']?[^\"'\n]+/(?:config/)?bashrc[\"']? \]; then\n    \. [\"']?[^\"'\n]+/(?:config/)?bashrc[\"']?\nfi\n*",
    "",
    content,
)
content = re.sub(r"# Source personal dotfiles configuration\nfi\n*", "", content)

target = f"{repo_dir}/config/bashrc"
loader = (
    f"\n\n# Source personal dotfiles configuration\n"
    f'if [ -f "{target}" ]; then\n'
    f'    . "{target}"\n'
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

    info "Linking maintenance scripts into ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    if [[ -f "$DOTFILES_DIR/scripts/updown.sh" ]]; then
        link_into "$DOTFILES_DIR/scripts/updown.sh" "$HOME/.local/bin/updown"
        success "Linked updown → $HOME/.local/bin/updown"
    fi

    if [[ -d "$DOTFILES_DIR/config/systemd" ]]; then
        info "Linking systemd user services..."
        local SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SYSTEMD_USER_DIR"
        for unit in "$DOTFILES_DIR/config/systemd"/*; do
            [[ -f "$unit" ]] || continue
            link_into "$unit" "$SYSTEMD_USER_DIR/$(basename "$unit")"
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
        success "systemd user units linked & enabled"
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
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
        info "KDE sycoca cache rebuilt"
    fi
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

    info "Configuring Spectacle save locations to ~/Downloads..."
    local SPECTACLE_CONFIG="$HOME/.config/spectaclerc"
    mkdir -p "$(dirname "$SPECTACLE_CONFIG")"
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file spectaclerc --group ImageSave --key imageSaveLocation "file://$HOME/Downloads"
        kwriteconfig6 --file spectaclerc --group ImageSave --key lastImageSaveLocation "file://$HOME/Downloads"
        kwriteconfig6 --file spectaclerc --group ImageSave --key lastImageSaveAsLocation "file://$HOME/Downloads"
        kwriteconfig6 --file spectaclerc --group VideoSave --key videoSaveLocation "file://$HOME/Downloads"
        kwriteconfig6 --file spectaclerc --group VideoSave --key lastVideoSaveLocation "file://$HOME/Downloads"
        kwriteconfig6 --file spectaclerc --group VideoSave --key lastVideoSaveAsLocation "file://$HOME/Downloads"
    else
        python3 - "$SPECTACLE_CONFIG" "$HOME/Downloads" << 'PY'
import sys, os, configparser, tempfile

path, dl_path = sys.argv[1], sys.argv[2]
dir_path = os.path.dirname(os.path.abspath(path))
os.makedirs(dir_path, exist_ok=True)

dl_url = f"file://{dl_path}"
config = configparser.RawConfigParser(delimiters=('=',), strict=False)
config.optionxform = str
if os.path.exists(path):
    config.read(path)

for sec, keys in [
    ("ImageSave", ["imageSaveLocation", "lastImageSaveLocation", "lastImageSaveAsLocation"]),
    ("VideoSave", ["videoSaveLocation", "lastVideoSaveLocation", "lastVideoSaveAsLocation"]),
]:
    if not config.has_section(sec):
        config.add_section(sec)
    for k in keys:
        config.set(sec, k, dl_url)

tmp_fd, tmp_path = tempfile.mkstemp(prefix=".spectaclerc.tmp.", dir=dir_path)
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        config.write(f, space_around_delimiters=False)
    os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, path)
except Exception:
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    raise
PY
    fi
    success "Spectacle configured to save screenshots and recordings to ~/Downloads"
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
            self_test_link_into
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
