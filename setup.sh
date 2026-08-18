#!/bin/bash
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash
#   setup.sh --dev      # Full dev stack, non-interactive
#   setup.sh --desktop  # Desktop essentials (Chrome + Insync  minimal)

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Repos/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/DerekRoberts/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"

# ── Bootstrap: ensure dotfiles repo is present ───────────────────────────────

ensure_dotfiles_repo() {
    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        echo "Cloning dotfiles to $DOTFILES_DIR..."
        mkdir -p "$(dirname "$DOTFILES_DIR")"
        command git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR"
    elif [[ -z "${DOTFILES_SKIP_PULL:-}" ]]; then
        local current_branch
        current_branch="$(command git -C "$DOTFILES_DIR" branch --show-current 2>/dev/null || true)"
        if [[ "$current_branch" == "$DOTFILES_BRANCH" ]]; then
            echo "Updating dotfiles ($DOTFILES_BRANCH)..."
            command git -C "$DOTFILES_DIR" pull --ff-only origin "$DOTFILES_BRANCH"
        else
            echo "Note: dotfiles on branch '$current_branch' — skipping pull (not on $DOTFILES_BRANCH)."
        fi
    fi
}

ensure_dotfiles_repo

# Re-exec from the cloned copy if running via pipe
SETUP_PATH="$(readlink -f "${BASH_SOURCE[0]:-}" 2>/dev/null || true)"
if [[ -z "$SETUP_PATH" ]] || [[ "$SETUP_PATH" != "$DOTFILES_DIR/setup.sh" ]]; then
    exec bash "$DOTFILES_DIR/setup.sh" "$@"
fi

REPO_DIR="$DOTFILES_DIR"
BASHRC="$HOME/.bashrc"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# ── Pure-Bash TUI checkbox menu ───────────────────────────────────────────────
# Arrow keys navigate, Space toggles, Enter confirms.
# Reads from /dev/tty so it works when stdin is piped.


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

        if command -v qdbus &>/dev/null; then
            qdbus org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.reparseConfiguration 2>/dev/null || true
        elif command -v qdbus6 &>/dev/null; then
            qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.reparseConfiguration 2>/dev/null || true
        elif command -v qdbus-qt6 &>/dev/null; then
            qdbus-qt6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.reparseConfiguration 2>/dev/null || true
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
        success "Insync already installed"
        local AUTOSTART_DIR="$HOME/.config/autostart"
        mkdir -p "$AUTOSTART_DIR"
        if [[ -f "$APPS_DIR/insync.desktop" ]]; then
            ln -sf "$APPS_DIR/insync.desktop" "$AUTOSTART_DIR/insync.desktop"
            success "Insync added to autostart"
        fi
        return
    fi

    info "Downloading/Updating Insync..."
    bash "$REPO_DIR/bin/updown" --install-insync

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
DESKTOP
    sed -i "s|%h|$HOME|g" "$APPS_DIR/insync.desktop"

    local AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    ln -sf "$APPS_DIR/insync.desktop" "$AUTOSTART_DIR/insync.desktop"

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
        restorecon -v "$CURSOR_BIN" 2>/dev/null || true
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
    if curl -fsSL "https://raw.githubusercontent.com/dietrichgebert/ponytail/main/.cursor/rules/ponytail.mdc" -o "$CURSOR_RULES_DIR/ponytail.mdc"; then
        success "Cursor rule downloaded to $CURSOR_RULES_DIR/ponytail.mdc"
    else
        warn "Failed to download Cursor rule"
    fi

    info "Configuring Ponytail for Antigravity (agy)..."
    local AGY_BIN="${HOME}/.local/bin/agy"
    if ! command -v agy &>/dev/null && [[ ! -x "$AGY_BIN" ]]; then
        warn "agy CLI not found. Run setup.sh --dev or agy update first. Skipping plugin install."
    else
        [[ -x "$AGY_BIN" ]] || AGY_BIN="agy"
        if "$AGY_BIN" plugin install https://github.com/DietrichGebert/ponytail 2>/dev/null; then
            success "agy plugin installed"
        else
            warn "agy plugin install failed (it might already be installed, or network issue)"
        fi
    fi
}




install_antigravity() {
    section "Antigravity Hub"
    local UPDATER="$REPO_DIR/bin/update-antigravity"
    if [[ ! -x "$UPDATER" ]]; then
        warn "bin/update-antigravity not found — skipping"
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
        restorecon -v "$AGY_BIN" 2>/dev/null || true
    fi
    success "agy CLI installed"
}

install_oc() {
    section "OpenShift CLI (oc)"
    bash "$REPO_DIR/scripts/bootstrap-tools.sh"
}

install_work_repos() {
    section "Work Repositories"
    bash "$REPO_DIR/scripts/clone-work-repos.sh"
}


install_ai_instructions() {
    section "AI Instructions"
    if [[ -f "$REPO_DIR/scripts/bundle-ai-instructions.sh" ]]; then
        bash "$REPO_DIR/scripts/bundle-ai-instructions.sh"
    fi
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
    if [[ -f "$REPO_DIR/config/kde/user-places.xbel" ]]; then
        mkdir -p "$HOME/.local/share"
        cp "$REPO_DIR/config/kde/user-places.xbel" "$HOME/.local/share/user-places.xbel"
        success "Dolphin sidebar cleaned"
    fi

    success "Directories configured (Documents, Downloads, Repos remain)"
}

wire_core() {
    section "Core Wiring"

    # 1. bashrc sourcing
    if [[ -f "$BASHRC" ]]; then
        info "Updating ~/.bashrc sourcing..."
        cp "$BASHRC" "$BASHRC.bak.$(date +%s)"

        python3 - "$BASHRC" "$REPO_DIR" << 'PY'
import sys, re
path, repo_dir = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()

content = re.sub(r".*/Documents/1-Personal/Linux/bashrc.*\n*", "", content)
content = re.sub(
    r"# Source personal dotfiles configuration\nif \[ -f \"[^\"]+/bashrc\" \]; then\n    \. \"[^\"]+/bashrc\"\nfi\n*",
    "",
    content,
)
content = re.sub(r"# Source personal dotfiles configuration\nfi\n*", "", content)

loader = (
    f"\n\n# Source personal dotfiles configuration\n"
    f'if [ -f "{repo_dir}/bashrc" ]; then\n'
    f'    . "{repo_dir}/bashrc"\n'
    f"fi\n"
)
with open(path, "w") as f:
    f.write(content.rstrip() + loader)
PY
        success "~/.bashrc sourcing updated"
    fi

    # 2. Git global include
    info "Configuring Git global settings..."
    command git config --global include.path "$REPO_DIR/gitconfig"
    success "Git include path set"

    if [[ -f "$REPO_DIR/scripts/git-setup.sh" ]]; then
        bash "$REPO_DIR/scripts/git-setup.sh"
    fi

    # 3. bin symlinks
    info "Symlinking bin scripts..."
    mkdir -p "$HOME/.local/bin"
    for script in updown update-antigravity tpm-enroll; do
        [[ -f "$REPO_DIR/bin/$script" ]] || { warn "bin/$script missing — skipping"; continue; }
        chmod +x "$REPO_DIR/bin/$script"
    done
    if [[ -f "$REPO_DIR/bin/updown" ]]; then
        ln -sf "$REPO_DIR/bin/updown" "$HOME/.local/bin/updown"
        success "Symlinked updown → $HOME/.local/bin/updown"
    fi

    # 4. Antigravity config symlinks
    info "Configuring Antigravity..."
    local ANTIGRAVITY_DIR="$HOME/.config/antigravity"
    mkdir -p "$ANTIGRAVITY_DIR"
    for f in instructions.json; do
        local src="$REPO_DIR/config/antigravity/$f"
        local dest="$ANTIGRAVITY_DIR/$f"
        [[ -f "$src" ]] || continue
        if [[ -f "$dest" && ! -L "$dest" ]]; then
            mv "$dest" "$dest.bak"
            info "Backed up $f to $f.bak"
        fi
        ln -sf "$src" "$dest"
    done
    if [[ -f "$HOME/.config/antigravity-flags.conf" && ! -L "$HOME/.config/antigravity-flags.conf" ]]; then
        mv "$HOME/.config/antigravity-flags.conf" "$HOME/.config/antigravity-flags.conf.bak"
    fi
    ln -sf "$REPO_DIR/config/antigravity/antigravity-flags.conf" "$HOME/.config/antigravity-flags.conf"
    success "Antigravity config symlinked"

    # 5. VS Code config symlinks
    local VSCODE_DIR="$HOME/.config/Code/User"
    if [[ -d "$VSCODE_DIR" ]]; then
        info "Configuring VS Code..."
        if [[ -f "$VSCODE_DIR/settings.json" && ! -L "$VSCODE_DIR/settings.json" ]]; then
            mv "$VSCODE_DIR/settings.json" "$VSCODE_DIR/settings.json.bak"
        fi
        ln -sf "$REPO_DIR/config/vscode/settings.json" "$VSCODE_DIR/settings.json"
        success "VS Code settings.json symlinked"
    else
        info "VS Code not found — skipping"
    fi

    # 6. AI instructions
    install_ai_instructions

    local GLOBAL_PROMPT_FILE="$HOME/.config/Code/User/prompts/global.instructions.md"

    # 7. Antigravity global instructions + skills
    info "Configuring Antigravity global instructions and skills..."
    mkdir -p "$HOME/.gemini/config" "$HOME/.gemini/antigravity"
    if [[ -L "$HOME/.gemini/GEMINI.md" || ! -f "$HOME/.gemini/GEMINI.md" ]]; then
        ln -sf "$GLOBAL_PROMPT_FILE" "$HOME/.gemini/GEMINI.md"
        success "Symlinked ~/.gemini/GEMINI.md → global instructions"
    else
        warn "~/.gemini/GEMINI.md is a physical file — skipping symlink"
    fi

    if [[ -d "$REPO_DIR/config/ai/skills" ]]; then
        mkdir -p "$HOME/.agents/skills"
        for skill_dir in "$REPO_DIR/config/ai/skills"/*; do
            [[ -d "$skill_dir" ]] || continue
            local skill_name; skill_name="$(basename "$skill_dir")"
            ln -sfn "$skill_dir" "$HOME/.agents/skills/$skill_name"
        done
        success "AI skills symlinked"
    fi

    if [[ -L "$HOME/.gemini/config/skills" || ! -d "$HOME/.gemini/config/skills" ]]; then
        ln -sfn "$HOME/.agents/skills" "$HOME/.gemini/config/skills"
    fi
    if [[ -L "$HOME/.gemini/antigravity/skills" || ! -d "$HOME/.gemini/antigravity/skills" ]]; then
        ln -sfn "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills"
    fi
    # Remove erroneous circular symlink
    [[ -L "$HOME/.agents/skills/skills" ]] && rm -f "$HOME/.agents/skills/skills"

    # 8. Cursor instructions
    local CURSOR_USER_DIR="$HOME/.config/Cursor/User"
    if [[ -d "$CURSOR_USER_DIR" ]]; then
        info "Configuring Cursor..."
        mkdir -p "$CURSOR_USER_DIR/prompts"
        if [[ -L "$CURSOR_USER_DIR/prompts/global.instructions.md" || ! -f "$CURSOR_USER_DIR/prompts/global.instructions.md" ]]; then
            ln -sf "$GLOBAL_PROMPT_FILE" "$CURSOR_USER_DIR/prompts/global.instructions.md"
            success "Cursor instructions symlinked"
        else
            warn "$CURSOR_USER_DIR/prompts/global.instructions.md is a physical file — skipping"
        fi
    fi


    # 10. Remove legacy Kilo symlink
    [[ -L "$HOME/.copilot.md" ]] && rm -f "$HOME/.copilot.md" && info "Removed legacy ~/.copilot.md"

    configure_user_dirs

    success "Core wiring complete"
}

# ── Profile presets ───────────────────────────────────────────────────────────

install_native_tools() {
    section "Native Dev Tools"
    local SYSTEM_PKGS="gh jq python3 podman-compose"
    info "Installing native system packages via rpm-ostree..."
    for pkg in $SYSTEM_PKGS; do
        if ! rpm-ostree status | grep -q "$pkg"; then
            rpm-ostree install --idempotent -y "$pkg" || true
        fi
    done
    info "Installing standalone binaries..."
    local BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    if [ ! -d "$HOME/.nvm" ]; then
        info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | PROFILE=/dev/null bash
        success "nvm installed"
    fi
    success "Native tools installed"
}

preset_desktop() {
    
    
    install_chrome
    install_yakuake
    install_insync
}

preset_dev() {
    install_native_tools
    
    
    install_chrome
    install_yakuake
    install_insync
    install_antigravity
    install_agy
    install_cursor
    install_ponytail
    install_oc
    install_work_repos
}




# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Usage:
  setup.sh [OPTIONS]

Default (no flags): full dev stack, same as --dev.

Options:
              Antigravity hub, agy CLI, Cursor, oc, work repos, auto-updater
              profile — no dev tools), auto-updater
  --help      Show this help

Environment variables:
  DOTFILES_DIR        Clone location (default: ~/Repos/dotfiles)
  DOTFILES_REPO       Clone URL (default: GitHub)
  DOTFILES_BRANCH     Branch (default: main)
  DOTFILES_SKIP_PULL  Set to skip git pull on existing clone
  UPDATE              Set UPDATE=1 to force re-download of oc binary
  OC_VERSION          Override oc version tag (default: latest)
EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "=== Bootstrapping Dotfiles (Fedora Kinoite ) ==="

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
    --help|-h)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
esac

echo ""
echo "✅ Setup complete!"
echo "   Run: source ~/.bashrc   (or restart terminal)"
