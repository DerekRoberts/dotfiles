#!/bin/bash
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash
#   setup.sh --dev      # Full dev stack, non-interactive
#   setup.sh --desktop  # Desktop essentials (Chrome + VLC + Insync minimal)

set -euo pipefail

# ── Bootstrap: self-location or curl/pipe clone ──────────────────────────────

SETUP_PATH="$(readlink -f "${BASH_SOURCE[0]:-}" 2>/dev/null || true)"

if [[ -n "$SETUP_PATH" && -f "$SETUP_PATH" ]]; then
    DOTFILES_DIR="$(cd "$(dirname "$SETUP_PATH")" && pwd)"
else
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Repos/dotfiles}"
    DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/DerekRoberts/dotfiles.git}"
    DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"

    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        echo "Cloning dotfiles to $DOTFILES_DIR..."
        mkdir -p "$(dirname "$DOTFILES_DIR")"
        command git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR"
    else
        echo "Updating dotfiles ($DOTFILES_BRANCH)..."
        command git -C "$DOTFILES_DIR" pull --ff-only origin "$DOTFILES_BRANCH" 2>/dev/null || true
    fi
    exec bash "$DOTFILES_DIR/setup.sh" "$@"
fi

BASHRC="$HOME/.bashrc"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# ── Installer functions ───────────────────────────────────────────────────────
# Each function is idempotent: checks for presence before acting.

# Ensure Flathub remote is configured (user scope)
ensure_flathub() {
    if ! flatpak remote-list --user 2>/dev/null | grep -q "flathub"; then
        info "Adding Flathub remote..."
        flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
}

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

install_cursor() {
    section "Cursor (AppImage)"
    local BIN_DIR="$HOME/.local/bin"
    local CURSOR_BIN="$BIN_DIR/cursor.AppImage"
    local APPS_DIR="$HOME/.local/share/applications"

    if [[ -x "$CURSOR_BIN" ]]; then
        success "Cursor already installed"
        return
    fi

    info "Fetching latest Cursor AppImage URL..."
    local CURSOR_URL
    CURSOR_URL="$(curl -fsSL \
        'https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable' \
        | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4 || true)"

    if [[ -z "$CURSOR_URL" ]]; then
        warn "Could not resolve Cursor download URL — skipping"
        warn "Manual download: https://www.cursor.com/downloads"
        return 1
    fi

    info "Downloading Cursor: $CURSOR_URL"
    mkdir -p "$BIN_DIR"
    curl -fsSL "$CURSOR_URL" -o "$CURSOR_BIN"
    chmod +x "$CURSOR_BIN"

    # Fix SELinux context
    if command -v restorecon &>/dev/null; then
        restorecon "$CURSOR_BIN" 2>/dev/null || true
    fi

    # Write version stamp for auto-updater
    local STAMP_FILE="$HOME/.local/share/dotfiles/cursor.url"
    mkdir -p "$(dirname "$STAMP_FILE")"
    echo "$CURSOR_URL" > "$STAMP_FILE"

    # Desktop entry
    mkdir -p "$APPS_DIR"
    cat > "$APPS_DIR/cursor.desktop" << DESKTOP
[Desktop Entry]
Name=Cursor
Comment=AI-first code editor
Exec=$CURSOR_BIN --no-sandbox %F
Icon=cursor
Terminal=false
Type=Application
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupNotify=true
StartupWMClass=Cursor
DESKTOP

    success "Cursor AppImage installed to $CURSOR_BIN"
}
install_ponytail() {
    section "Ponytail (Lazy Senior Dev)"
    
    info "Configuring Ponytail for Cursor..."
    local CURSOR_RULES_DIR="$HOME/.cursor/rules"
    mkdir -p "$CURSOR_RULES_DIR"
    if [[ -f "$CURSOR_RULES_DIR/ponytail.mdc" ]]; then
        success "Cursor rule already present"
    else
        if curl -fsSL "https://raw.githubusercontent.com/dietrichgebert/ponytail/main/.cursor/rules/ponytail.mdc" -o "$CURSOR_RULES_DIR/ponytail.mdc"; then
            success "Cursor rule downloaded to $CURSOR_RULES_DIR/ponytail.mdc"
        else
            warn "Failed to download Cursor rule"
        fi
    fi

    info "Configuring Ponytail for Antigravity (agy)..."
    local AGY_BIN="${HOME}/.local/bin/agy"
    if ! command -v agy &>/dev/null && [[ ! -x "$AGY_BIN" ]]; then
        warn "agy CLI not found. Run setup.sh --dev or agy update first. Skipping plugin install."
    else
        [[ -x "$AGY_BIN" ]] || AGY_BIN="agy"
        local PLUGIN_DIR="$HOME/.gemini/config/plugins/ponytail"
        if [[ -d "$PLUGIN_DIR" ]] || "$AGY_BIN" plugin list 2>/dev/null | grep -q '"name": "ponytail"'; then
            success "Ponytail plugin already installed for agy"
        else
            if "$AGY_BIN" plugin install https://github.com/DietrichGebert/ponytail 2>/dev/null; then
                success "agy plugin installed"
            else
                warn "agy plugin install failed (network issue or repo error)"
            fi
        fi
    fi
}
install_antigravity() {
    section "Antigravity Hub"
    local UPDATER="$DOTFILES_DIR/scripts/update-antigravity.sh"
    if [[ ! -f "$UPDATER" ]]; then
        warn "scripts/update-antigravity.sh not found — skipping"
        return
    fi
    bash "$UPDATER"

    # Desktop entry for the Antigravity hub
    local ANTI_BIN="$HOME/.local/bin/antigravity/antigravity"
    local APPS_DIR="$HOME/.local/share/applications"
    if [[ -f "$ANTI_BIN" ]]; then
        mkdir -p "$APPS_DIR"
        cat > "$APPS_DIR/antigravity.desktop" << DESKTOP
[Desktop Entry]
Name=Antigravity
Comment=AI coding assistant
Exec=$ANTI_BIN
Icon=antigravity
Terminal=false
Type=Application
Categories=Development;
StartupNotify=true
StartupWMClass=Antigravity
DESKTOP
        success "Antigravity hub installed with desktop entry"
    fi
}

install_agy() {
    section "agy CLI"
    local AGY_BIN="$HOME/.local/bin/agy"

    # Check current version before downloading
    if [[ -x "$AGY_BIN" ]]; then
        success "agy already installed: $("$AGY_BIN" --version 2>/dev/null || echo 'unknown version')"
        info "To force update: curl -fsSL https://antigravity.google/cli/install.sh | bash"
        return
    fi

    info "Installing agy CLI..."
    curl -fsSL https://antigravity.google/cli/install.sh | bash

    if command -v restorecon &>/dev/null && [[ -f "$AGY_BIN" ]]; then
        restorecon "$AGY_BIN" 2>/dev/null || true
    fi
    success "agy CLI installed"
}

install_oc() {
    section "OpenShift CLI (oc)"
    bash "$DOTFILES_DIR/scripts/bootstrap-tools.sh"
}

install_repos() {
    section "Repositories"
    bash "$DOTFILES_DIR/scripts/clone-repos.sh" || warn "Some repositories could not be cloned. Run 'scripts/clone-repos.sh' once your SSH key is authorized on GitHub."
}

# ── Core wiring (always runs regardless of profile) ──────────────────────────

configure_user_dirs() {
    section "XDG User Directories"
    
    local CONFIG_FILE="$HOME/.config/user-dirs.dirs"
    info "Writing strict XDG directory definitions..."
    
    mkdir -p "$HOME/.config"
    cat > "$CONFIG_FILE" << EOF
XDG_DESKTOP_DIR="$HOME/Downloads/"
XDG_DOCUMENTS_DIR="$HOME/Documents/"
XDG_DOWNLOAD_DIR="$HOME/Downloads/"
XDG_MUSIC_DIR="$HOME/Documents/"
XDG_PICTURES_DIR="$HOME/Documents/"
XDG_PROJECTS_DIR="$HOME/Documents/"
XDG_PUBLICSHARE_DIR="$HOME/Documents/"
XDG_TEMPLATES_DIR="$HOME/Documents/"
XDG_VIDEOS_DIR="$HOME/Documents/"
EOF

    # Prevent xdg-user-dirs-update from recreating the default folders
    echo "enabled=False" > "$HOME/.config/user-dirs.conf"

    info "Cleaning up unused default directories (if empty)..."
    for dir in Desktop Music Pictures Public Templates Videos; do
        if [[ -d "$HOME/$dir" ]]; then
            rmdir "$HOME/$dir" 2>/dev/null || true
        fi
    done
    
    info "Overwriting Dolphin sidebar places with clean template..."
    if [[ -f "$DOTFILES_DIR/config/kde/user-places.xbel" ]]; then
        mkdir -p "$HOME/.local/share"
        sed "s|/var/home/derek|$HOME|g" "$DOTFILES_DIR/config/kde/user-places.xbel" > "$HOME/.local/share/user-places.xbel"
        success "Dolphin sidebar cleaned"
    fi

    # Configure natural/inverted scrolling globally for all current and connected mice/touchpads
    if command -v kwriteconfig6 &>/dev/null || [[ -f "$HOME/.config/kcminputrc" ]]; then
        info "Configuring natural scrolling globally for all devices in KDE..."
        
        # 1. Global fallback groups
        if command -v kwriteconfig6 &>/dev/null; then
            kwriteconfig6 --file kcminputrc --group Mouse --key NaturalScroll true
            kwriteconfig6 --file kcminputrc --group Mouse --key XLbInptNaturalScroll true
            kwriteconfig6 --file kcminputrc --group Touchpad --key NaturalScroll true
            kwriteconfig6 --file kcminputrc --group Touchpad --key XLbInptNaturalScroll true
        fi
        
        # 2. Discover all connected hardware pointers and ensure every section in kcminputrc has NaturalScroll=true
        python3 - "$HOME/.config/kcminputrc" << 'PY'
import sys, re, os, subprocess

path = sys.argv[1]
discovered_devices = []

# Query live KWin InputDeviceManager on D-Bus if available
try:
    cmd = ["qdbus-qt6", "org.kde.KWin", "/org/kde/KWin/InputDevice", "org.kde.KWin.InputDeviceManager.ListPointers"]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
    if res.returncode == 0:
        for dev in res.stdout.strip().splitlines():
            dev = dev.strip()
            if not dev:
                continue
            dev_path = f"/org/kde/KWin/InputDevice/{dev}"
            def get_prop(prop):
                r = subprocess.run(["qdbus-qt6", "org.kde.KWin", dev_path, "org.freedesktop.DBus.Properties.Get", "org.kde.KWin.InputDevice", prop], capture_output=True, text=True, timeout=1)
                return r.stdout.strip()
            
            supports = get_prop("supportsNaturalScroll")
            if supports.lower() == "true":
                vendor = get_prop("vendor")
                product = get_prop("product")
                name = get_prop("name")
                if vendor and product and name:
                    discovered_devices.append((vendor, product, name))
                    # Apply live to active session
                    subprocess.run(["qdbus-qt6", "org.kde.KWin", dev_path, "org.freedesktop.DBus.Properties.Set", "org.kde.KWin.InputDevice", "naturalScroll", "true"], capture_output=True, timeout=1)
except Exception:
    pass

# Supplementary hardware discovery via /proc/bus/input/devices
proc_path = "/proc/bus/input/devices"
if os.path.exists(proc_path):
    try:
        with open(proc_path, "r") as f:
            content = f.read()
        for b in content.strip().split("\n\n"):
            handlers = re.search(r"H: Handlers=.*(mouse|event).*", b)
            if not handlers:
                continue
            name_match = re.search(r'N: Name="([^"]+)"', b)
            id_match = re.search(r"I: Bus=(\w+) Vendor=(\w+) Product=(\w+)", b)
            if name_match and id_match:
                name = name_match.group(1)
                vendor_hex = id_match.group(2)
                product_hex = id_match.group(3)
                vendor_dec = str(int(vendor_hex, 16))
                product_dec = str(int(product_hex, 16))
                if any(k in name.lower() for k in ("mouse", "touchpad", "trackpoint", "trackball", "pointer")):
                    discovered_devices.append((vendor_dec, product_dec, name))
    except Exception:
        pass

lines = []
if os.path.exists(path):
    with open(path, "r") as f:
        lines = f.readlines()

new_lines = []
in_target = False
found_natural = False
target_keys = ("NaturalScroll", "XLbInptNaturalScroll")
seen_sections = set()

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_target and not found_natural:
            new_lines.append("NaturalScroll=true\n")
        in_target = "Libinput" in stripped or stripped in ("[Mouse]", "[Touchpad]")
        found_natural = False
        seen_sections.add(stripped)
        new_lines.append(line)
        continue

    if in_target and any(stripped.startswith(k + "=") for k in target_keys):
        new_lines.append(re.sub(r"=\s*(false|0)", "=true", line))
        found_natural = True
        continue

    new_lines.append(line)

if in_target and not found_natural:
    new_lines.append("NaturalScroll=true\n")

# Append newly discovered device sections if missing
for v, p, n in set(discovered_devices):
    section_hdr = f"[Libinput][{v}][{p}][{n}]"
    if section_hdr not in seen_sections:
        new_lines.append(f"\n{section_hdr}\nNaturalScroll=true\n")
        seen_sections.add(section_hdr)

os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
with open(path, "w") as f:
    f.writelines(new_lines)
PY
        
        # Notify KWin / KDE input daemon of configuration changes
        if command -v qdbus-qt6 &>/dev/null; then
            qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        elif command -v qdbus6 &>/dev/null; then
            qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        elif command -v qdbus &>/dev/null; then
            qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        fi
        success "Natural scrolling enabled for all connected and configured devices"
    fi

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

    # Configure KDE Plasma Desktops (Layout=Desktop, DarkestHour wallpaper), Panel layout & System Tray visibility
    info "Configuring KDE Plasma desktops (DarkestHour wallpaper), panel & task manager (Dolphin, Chrome)..."
    local PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    local WAS_PLASMASHELL_ACTIVE=false
    if command -v systemctl &>/dev/null && systemctl --user is-active plasma-plasmashell &>/dev/null; then
        WAS_PLASMASHELL_ACTIVE=true
        systemctl --user stop plasma-plasmashell >/dev/null 2>&1 || true
    fi

    if [[ -f "$PLASMA_CONFIG" ]]; then
        python3 - "$PLASMA_CONFIG" << 'PY'
import sys, os, re

path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)

with open(path, "r") as f:
    content = f.read()

# 1. Ensure all desktop containments use org.kde.desktopcontainment
lines = content.splitlines(True)
new_lines = []
in_desktop = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[Containments][") and stripped.endswith("]"):
        parts = stripped[1:-1].split("][")
        in_desktop = len(parts) == 2
    elif stripped.startswith("["):
        in_desktop = False
    elif in_desktop and stripped == "plugin=org.kde.plasma.folder":
        line = "plugin=org.kde.desktopcontainment\n"
    new_lines.append(line)

content = "".join(new_lines)

# 2. System Tray sub-applets & visibility preferences
core_plugins = [
    "org.kde.plasma.volume",
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.brightness",
    "org.kde.plasma.notifications",
    "org.kde.plasma.clipboard",
    "org.kde.plasma.devicenotifier",
    "org.kde.plasma.cameraindicator",
    "org.kde.kdeconnect",
    "org.kde.plasma.vault",
    "org.kde.kscreen"
]

tray_hdr = None
for m in re.finditer(r"^(\[Containments\]\[\d+\]\[Applets\]\[\d+\])\s*$", content, re.M):
    hdr = m.group(1)
    body_end = content.find("\n[", m.end())
    body = content[m.end():body_end if body_end != -1 else len(content)]
    if "plugin=org.kde.plasma.systemtray" in body:
        tray_hdr = hdr
        break

if tray_hdr:
    # Collect existing child applet IDs and plugins
    existing_ids = [int(m) for m in re.findall(re.escape(tray_hdr) + r"\[Applets\]\[(\d+)\]", content)]
    next_id = max(existing_ids) + 1 if existing_ids else 30
    
    existing_plugins = []
    for m in re.finditer(re.escape(tray_hdr) + r"\[Applets\]\[\d+\][\s\S]*?plugin=([\w\.\-]+)", content):
        existing_plugins.append(m.group(1))
    
    # Add missing core child applets
    additions = []
    for plugin in core_plugins:
        if plugin not in existing_plugins:
            additions.append(f"\n{tray_hdr}[Applets][{next_id}]\nimmutability=1\nplugin={plugin}\n")
            next_id += 1
    
    if additions:
        content += "".join(additions)

    # Ensure [General] section exists with exact user preferences
    gen_hdr = f"{tray_hdr}[General]"
    gen_prefs = {
        "disabledStatusNotifiers": "org.kde.yakuake",
        "shownItems": "Insync,org.kde.plasma.volume,org.kde.plasma.networkmanagement",
        "hiddenItems": "Antigravity_status_icon_1,Xwayland Video Bridge,org.kde.plasma.cameraindicator,org.kde.kdeconnect,org.kde.plasma.clipboard,org.kde.plasma.notifications,chrome_status_icon_1@cursor,org.kde.plasma.bluetooth,org.kde.plasma.devicenotifier,org.kde.plasma.brightness",
        "extraItems": "org.kde.plasma.battery,org.kde.plasma.devicenotifier,org.kde.plasma.networkmanagement,org.kde.plasma.printmanager,org.kde.plasma.volume,org.kde.plasma.bluetooth,org.kde.plasma.cameraindicator,org.kde.kdeconnect,org.kde.plasma.clipboard,org.kde.plasma.notifications,org.kde.plasma.brightness,org.kde.kscreen"
    }
    
    if gen_hdr in content:
        lines = content.splitlines(True)
        out_lines = []
        in_gen = False
        seen_keys = set()
        for line in lines:
            stripped = line.strip()
            if stripped == gen_hdr:
                in_gen = True
                out_lines.append(line)
                continue
            elif stripped.startswith("[") and stripped.endswith("]"):
                if in_gen:
                    for k, v in gen_prefs.items():
                        if k not in seen_keys:
                            out_lines.append(f"{k}={v}\n")
                    in_gen = False
                out_lines.append(line)
                continue
            
            if in_gen:
                matched = False
                for k, v in gen_prefs.items():
                    if stripped.startswith(f"{k}="):
                        out_lines.append(f"{k}={v}\n")
                        seen_keys.add(k)
                        matched = True
                        break
                if not matched:
                    out_lines.append(line)
                continue
            out_lines.append(line)
        if in_gen:
            for k, v in gen_prefs.items():
                if k not in seen_keys:
                    out_lines.append(f"{k}={v}\n")
        content = "".join(out_lines)
    else:
        gen_block = f"\n{gen_hdr}\n" + "\n".join(f"{k}={v}" for k, v in gen_prefs.items()) + "\n"
        content += gen_block

with open(path, "w") as f:
    f.write(content)
PY
    fi

    if [[ "$WAS_PLASMASHELL_ACTIVE" == true ]]; then
        systemctl --user start plasma-plasmashell >/dev/null 2>&1 || true
        for _ in {1..25}; do
            if qdbus-qt6 org.kde.plasmashell &>/dev/null || qdbus6 org.kde.plasmashell &>/dev/null || qdbus org.kde.plasmashell &>/dev/null; then
                break
            fi
            sleep 0.2
        done
    fi

    local PANEL_SCRIPT='
var d = desktops();
for (var i = 0; i < d.length; i++) {
    d[i].writeConfig("plugin", "org.kde.desktopcontainment");
    d[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d[i].writeConfig("Image", "/usr/share/wallpapers/DarkestHour");
    d[i].reloadConfig();
}
var p = panels();
for (var i = 0; i < p.length; i++) {
    p[i].location = "left";
    p[i].hiding = "dodgewindows";
    p[i].height = 72;
    var ws = p[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === "org.kde.plasma.showdesktop" || ws[j].type === "org.kde.plasma.peekatdesktop") {
            ws[j].remove();
        } else if (ws[j].type === "org.kde.plasma.icontasks") {
            ws[j].currentConfigGroup = ["General"];
            ws[j].writeConfig("launchers", "applications:org.kde.dolphin.desktop,applications:com.google.Chrome.desktop");
            ws[j].reloadConfig();
        }
    }
}
'
    if command -v qdbus-qt6 &>/dev/null; then
        qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    elif command -v qdbus6 &>/dev/null; then
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    elif command -v qdbus &>/dev/null; then
        qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    fi

    success "Desktops (DarkestHour), panel layout & task manager configured"

    success "Directories, input, panel, and defaults configured"
}


wire_core() {
    section "Core Wiring"

    # 1. bashrc sourcing
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

    # 2. Git global include
    info "Configuring Git global settings..."
    command git config --global include.path "$DOTFILES_DIR/config/gitconfig"
    success "Git include path set"

    if [[ -f "$DOTFILES_DIR/scripts/git-setup.sh" ]]; then
        bash "$DOTFILES_DIR/scripts/git-setup.sh"
    fi

    # 3. User CLI tools & update service
    info "Installing maintenance scripts to ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    if [[ -f "$DOTFILES_DIR/scripts/updown.sh" ]]; then
        install -m 755 "$DOTFILES_DIR/scripts/updown.sh" "$HOME/.local/bin/updown"
        success "Installed updown → $HOME/.local/bin/updown"
    fi
    if [[ -f "$DOTFILES_DIR/scripts/update-antigravity.sh" ]]; then
        install -m 755 "$DOTFILES_DIR/scripts/update-antigravity.sh" "$HOME/.local/bin/update-antigravity"
        success "Installed update-antigravity → $HOME/.local/bin/update-antigravity"
    fi

    if [[ -f "$DOTFILES_DIR/config/systemd/dotfiles-update.service" ]]; then
        info "Configuring update service..."
        local SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SYSTEMD_USER_DIR"
        cp -f "$DOTFILES_DIR/config/systemd/dotfiles-update.service" "$SYSTEMD_USER_DIR/dotfiles-update.service"
        if command -v systemctl &>/dev/null; then
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            systemctl --user enable dotfiles-update.service >/dev/null 2>&1 || true
        fi
        success "dotfiles-update.service installed & enabled"
    fi

    # 4. Antigravity global instructions + skills
    local INSTRUCTIONS_FILE="$DOTFILES_DIR/config/instructions.md"
    info "Configuring Antigravity global instructions and skills..."
    mkdir -p "$HOME/.gemini/config" "$HOME/.gemini/antigravity" "$HOME/.agents/skills"
    if [[ -f "$INSTRUCTIONS_FILE" ]]; then
        rm -f "$HOME/.gemini/GEMINI.md"
        cp -f "$INSTRUCTIONS_FILE" "$HOME/.gemini/GEMINI.md"
        success "Installed ~/.gemini/GEMINI.md"
    fi

    if [[ -d "$DOTFILES_DIR/config/skills" ]]; then
        for skill_dir in "$DOTFILES_DIR/config/skills"/*; do
            [[ -d "$skill_dir" ]] || continue
            local skill_name; skill_name="$(basename "$skill_dir")"
            rm -rf "$HOME/.agents/skills/$skill_name"
            cp -rf "$skill_dir" "$HOME/.agents/skills/$skill_name"
        done
        success "AI skills installed"
    fi

    if [[ -L "$HOME/.gemini/config/skills" || ! -d "$HOME/.gemini/config/skills" ]]; then
        ln -sfn "$HOME/.agents/skills" "$HOME/.gemini/config/skills"
    fi
    if [[ -L "$HOME/.gemini/antigravity/skills" || ! -d "$HOME/.gemini/antigravity/skills" ]]; then
        ln -sfn "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills"
    fi
    [[ -L "$HOME/.agents/skills/skills" ]] && rm -f "$HOME/.agents/skills/skills"

    # 5. Cursor instructions
    local CURSOR_USER_DIR="$HOME/.config/Cursor/User"
    if [[ -f "$INSTRUCTIONS_FILE" ]]; then
        info "Configuring Cursor..."
        mkdir -p "$CURSOR_USER_DIR/prompts"
        rm -f "$CURSOR_USER_DIR/prompts/global.instructions.md"
        cp -f "$INSTRUCTIONS_FILE" "$CURSOR_USER_DIR/prompts/global.instructions.md"
        success "Cursor instructions installed"
    fi

    # 6. Remove legacy Kilo symlink
    [[ -L "$HOME/.copilot.md" ]] && rm -f "$HOME/.copilot.md" && info "Removed legacy ~/.copilot.md"

    # 7. Global git hooks
    local HOOKS_SRC_DIR="$DOTFILES_DIR/config/hooks"
    local HOOKS_DEST_DIR="$HOME/.githooks"
    if [[ -d "$HOOKS_SRC_DIR" ]]; then
        info "Installing global git hooks..."
        mkdir -p "$HOOKS_DEST_DIR"
        for hook_file in "$HOOKS_SRC_DIR"/*; do
            [[ -f "$hook_file" ]] || continue
            local hook_name; hook_name="$(basename "$hook_file")"
            cp -f "$hook_file" "$HOOKS_DEST_DIR/$hook_name"
            chmod +x "$HOOKS_DEST_DIR/$hook_name"
        done
        success "Global git hooks installed → $HOOKS_DEST_DIR"
    fi

    configure_user_dirs

    success "Core wiring complete"
}

# ── Profile presets ───────────────────────────────────────────────────────────

install_native_tools() {
    section "Native Dev Tools"
    info "Installing standalone binaries..."
    local BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    # jq
    if ! command -v jq &>/dev/null; then
        info "Downloading jq..."
        curl -fsSL "https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64" -o "$BIN_DIR/jq"
        chmod +x "$BIN_DIR/jq"
    fi

    # gh
    if ! command -v gh &>/dev/null; then
        info "Downloading gh..."
        local tmp_dir; tmp_dir="$(mktemp -d)"
        # Get latest version using grep since we might not have jq yet if it fails
        local gh_latest; gh_latest=$(curl -sI https://github.com/cli/cli/releases/latest | grep -i "^location:" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" || echo "v2.54.0")
        gh_latest=${gh_latest#v}
        curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_latest}/gh_${gh_latest}_linux_amd64.tar.gz" | tar -xz -C "$tmp_dir"
        mv "$tmp_dir/gh_${gh_latest}_linux_amd64/bin/gh" "$BIN_DIR/gh"
        chmod +x "$BIN_DIR/gh"
        rm -rf "$tmp_dir"
    fi

    # gitleaks
    if ! command -v gitleaks &>/dev/null; then
        info "Downloading gitleaks..."
        local tmp_dir; tmp_dir="$(mktemp -d)"
        local gitleaks_version="8.24.0"
        local gitleaks_url="https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_version}/gitleaks_${gitleaks_version}_linux_x64.tar.gz"
        if curl -fsSL "$gitleaks_url" -o "$tmp_dir/gitleaks.tar.gz"; then
            tar -xzf "$tmp_dir/gitleaks.tar.gz" -C "$tmp_dir" gitleaks
            mv "$tmp_dir/gitleaks" "$BIN_DIR/gitleaks"
            chmod +x "$BIN_DIR/gitleaks"
        else
            warn "Failed to download gitleaks v${gitleaks_version}"
        fi
        rm -rf "$tmp_dir"
    fi

    # podman-compose
    if ! command -v podman-compose &>/dev/null; then
        info "Downloading podman-compose..."
        curl -fsSL "https://raw.githubusercontent.com/containers/podman-compose/main/podman_compose.py" -o "$BIN_DIR/podman-compose"
        chmod +x "$BIN_DIR/podman-compose"
    fi
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | PROFILE=/dev/null bash
        success "nvm installed"
    fi

    # Ensure Node LTS is installed via NVM
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck source=/dev/null
        \. "$NVM_DIR/nvm.sh"
        info "Ensuring Node LTS is installed..."
        nvm install --lts >/dev/null 2>&1
        nvm alias default 'lts/*' >/dev/null 2>&1
        success "Node LTS installed & set as default"
    fi
    success "Native tools installed"
}

preset_desktop() {
    install_chrome
    install_vlc
    install_insync
}

preset_dev() {
    install_native_tools
    install_chrome
    install_vlc
    install_yakuake
    install_insync
    install_antigravity
    install_agy
    install_cursor
    install_ponytail
    install_oc
    install_repos
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Usage:
  setup.sh [OPTIONS]

Default (no flags): full dev stack, same as --dev.

Options:
  --dev       Full developer stack: Node LTS, CLI tools, Chrome, VLC, Yakuake, Insync,
              Antigravity hub, agy CLI, Cursor, oc, Ponytail, and repositories
  --desktop   Minimal desktop essentials: Chrome, VLC, and Insync
  --help, -h  Show this help

Environment variables:
  UPDATE              Set UPDATE=1 to force re-download of oc binary
  OC_VERSION          Override oc version tag (default: latest)
EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --dev|--desktop|"")
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
esac

echo "=== Bootstrapping Dotfiles (Fedora Kinoite) ==="

# Always wire core configs (bashrc, git, symlinks)
wire_core

case "${1:-}" in
    --dev|"")
        echo "Profile: dev (full stack)"
        preset_dev
        ;;
    --desktop)
        echo "Profile: desktop (essentials)"
        preset_desktop
        ;;
esac

echo ""
echo "✅ Setup complete!"
echo "   Run: source ~/.bashrc   (or restart terminal)"
if [[ -f "$DOTFILES_DIR/scripts/tpm-enroll.sh" ]]; then
    echo "   Optional: To enable TPM 2.0 LUKS auto-unlock, run:"
    echo "             $DOTFILES_DIR/scripts/tpm-enroll.sh"
fi
