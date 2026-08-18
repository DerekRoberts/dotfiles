#!/bin/bash
# setup.sh — Declarative workstation setup for Fedora 44 Kinoite + Nix/Home-Manager
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash
#   setup.sh --dev      # Full dev stack, non-interactive
#   setup.sh --desktop  # Desktop essentials (Chrome + Insync + Nix minimal)
#   setup.sh --custom   # TUI checkbox menu
#   setup.sh            # TUI checkbox menu (same as --custom)

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

tui_menu() {
    local -n _tui_items="$1"
    local -n _tui_selected="$2"
    local title="${3:-Select components}"

    local num=${#_tui_items[@]}
    local cursor=0
    local checked=()
    for ((i = 0; i < num; i++)); do
        checked+=("${_tui_selected[$i]:-0}")
    done

    # Requires a terminal
    local tty="/dev/tty"
    [[ -c "$tty" ]] && { true <"$tty"; } 2>/dev/null || {
        warn "No TTY available — defaulting to all items selected."
        for ((i = 0; i < num; i++)); do _tui_selected[$i]=1; done
        return
    }

    _tui_draw() {
        tput clear <"$tty"
        echo "  $title" >"$tty"
        echo "  (↑↓ navigate, Space toggle, Enter confirm)" >"$tty"
        echo "" >"$tty"
        for ((i = 0; i < num; i++)); do
            local box="[ ]"
            [[ "${checked[$i]}" == "1" ]] && box="[x]"
            if [[ "$i" == "$cursor" ]]; then
                echo "  > $box ${_tui_items[$i]}" >"$tty"
            else
                echo "    $box ${_tui_items[$i]}" >"$tty"
            fi
        done
    }

    _tui_draw
    while IFS= read -rsn1 -t 60 key <"$tty" 2>/dev/null; do
        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 -t 0.1 seq <"$tty" 2>/dev/null || seq=""
                case "$seq" in
                    "[A") ((cursor > 0)) && ((cursor--)) ;;          # Up
                    "[B") ((cursor < num - 1)) && ((cursor++)) ;;    # Down
                esac
                ;;
            " ")  # Space = toggle
                checked[$cursor]=$(( 1 - checked[$cursor] ))
                ;;
            "")   # Enter = confirm
                break ;;
        esac
        _tui_draw
    done

    tput clear <"$tty" 2>/dev/null || true
    for ((i = 0; i < num; i++)); do
        _tui_selected[$i]="${checked[$i]}"
    done
}

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

    info "Setting Yakuake toggle shortcut to Ctrl+Space..."
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kglobalshortcutsrc --group yakuake --key toggle-window-state "Ctrl+Space,F12,Open/Retract Yakuake"
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

    info "Resolving latest Insync RPM for Fedora..."
    # The downloads page is JS-rendered; the real URLs live in linux_download_links.js.
    # Prefer fc44 (Kinoite target), fall back to the newest Fedora build available.
    local INSYNC_JS_URL="https://cdn.insynchq.com/web/webflow/js/linux_download_links.js"
    local INSYNC_RPM_URL
    INSYNC_RPM_URL="$(curl -fsSL "$INSYNC_JS_URL" \
        | grep -oE 'https://cdn\.insynchq\.com/builds/linux/[^"]+\.x86_64\.rpm' \
        | grep -v 'headless' \
        | grep 'fc44' | head -n 1 || true)"

    # Fall back to newest available Fedora build if fc44 not yet listed
    if [[ -z "$INSYNC_RPM_URL" ]]; then
        INSYNC_RPM_URL="$(curl -fsSL "$INSYNC_JS_URL" \
            | grep -oE 'https://cdn\.insynchq\.com/builds/linux/[^"]+\.x86_64\.rpm' \
            | grep -v 'headless' \
            | grep -E 'fc[0-9]+' | sort -t'c' -k2 -rn | head -n 1 || true)"
    fi

    if [[ -z "$INSYNC_RPM_URL" ]]; then
        warn "Could not resolve Insync RPM URL — skipping"
        warn "Manual install: https://www.insynchq.com/downloads"
        return 1
    fi

    info "Downloading Insync RPM: $INSYNC_RPM_URL"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    curl -fsSL "$INSYNC_RPM_URL" -o "$tmp_dir/insync.rpm"

    # Extract RPM contents without installing (no root, no rpm-ostree)
    info "Extracting Insync binaries..."
    if ! command -v rpm2cpio &>/dev/null; then
        warn "rpm2cpio not found — cannot extract Insync RPM"
        warn "rpm2cpio is part of the base Fedora Kinoite image. This is unexpected."
        return 1
    fi

    (cd "$tmp_dir" && rpm2cpio insync.rpm | cpio -idm 2>/dev/null)

    mkdir -p "$BIN_DIR"
    # Find the insync binary inside the extracted tree
    local extracted_bin
    extracted_bin="$(find "$tmp_dir" -type f -name "insync" -not -name "*.py" | head -n 1 || true)"
    if [[ -z "$extracted_bin" ]]; then
        warn "insync binary not found in RPM — package structure may have changed"
        return 1
    fi

    cp "$extracted_bin" "$INSYNC_BIN"
    chmod +x "$INSYNC_BIN"

    # Fix SELinux context
    if command -v restorecon &>/dev/null; then
        restorecon -v "$INSYNC_BIN" 2>/dev/null || true
    fi

    # Write version stamp for auto-updater
    local STAMP_FILE="$HOME/.local/share/dotfiles/insync.url"
    mkdir -p "$(dirname "$STAMP_FILE")"
    echo "$INSYNC_RPM_URL" > "$STAMP_FILE"

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


install_nix() {
    section "Nix (Fedora Native)"

    if command -v nix &>/dev/null && [[ -d /nix ]]; then
        success "Nix is installed."
        
        # Ensure flakes are enabled
        local NIX_CONF_DIR="$HOME/.config/nix"
        mkdir -p "$NIX_CONF_DIR"
        if ! grep -q "experimental-features" "$NIX_CONF_DIR/nix.conf" 2>/dev/null; then
            echo "experimental-features = nix-command flakes" >> "$NIX_CONF_DIR/nix.conf"
            success "Enabled Nix flakes in $NIX_CONF_DIR/nix.conf"
        fi

        # Try to ensure daemon is active, prompt for sudo if necessary
        if ! systemctl status nix-daemon.socket &>/dev/null; then
            info "Enabling nix-daemon.socket (requires sudo)..."
            sudo systemctl enable --now nix-daemon.socket || true
        fi
        return
    fi

    info "Installing Nix via rpm-ostree..."
    
    if rpm-ostree status | grep -q " nix"; then
        warn "Nix is staged but not active. A reboot is required to mount /nix."
        warn "Please REBOOT and run ./setup.sh again to continue setup."
        exit 0
    else
        # Try to apply live
        if rpm-ostree install --idempotent --apply-live -y nix; then
            success "Nix installed and applied live!"
            local NIX_CONF_DIR="$HOME/.config/nix"
            mkdir -p "$NIX_CONF_DIR"
            if ! grep -q "experimental-features" "$NIX_CONF_DIR/nix.conf" 2>/dev/null; then
                echo "experimental-features = nix-command flakes" >> "$NIX_CONF_DIR/nix.conf"
            fi
            if ! systemctl status nix-daemon.socket &>/dev/null; then
                info "Enabling nix-daemon.socket (requires sudo)..."
                sudo systemctl enable --now nix-daemon.socket || true
            fi
        else
            warn "Live apply failed (expected for sysusers/daemons on immutable roots)."
            info "Falling back to standard staging install..."
            rpm-ostree install --idempotent -y nix
            warn "Nix has been successfully staged."
            warn "A REBOOT IS REQUIRED to mount /nix and initialize the daemon."
            warn "Please REBOOT and run ./setup.sh again."
            exit 0
        fi
    fi
}

install_home_manager() {
    section "Home-Manager"
    local profile="${1:-dev}"
    local HM_FLAKE="$REPO_DIR/config/home-manager"

    if ! command -v nix &>/dev/null; then
        warn "Nix not found in PATH — skipping home-manager setup"
        return
    fi

    if ! command -v home-manager &>/dev/null; then
        info "Bootstrapping home-manager..."
        nix run "nixpkgs#home-manager" -- init --switch --flake "$HM_FLAKE#$profile"
    else
        info "Applying home-manager switch (profile: $profile)..."
        home-manager switch --flake "$HM_FLAKE#$profile"
    fi

    # Persist profile choice for updown auto-updater
    if ! grep -q "DOTFILES_PROFILE" "$BASHRC" 2>/dev/null; then
        echo "" >> "$BASHRC"
        echo "# Dotfiles profile (used by bin/updown for home-manager switch)" >> "$BASHRC"
        echo "export DOTFILES_PROFILE=\"$profile\"" >> "$BASHRC"
    else
        sed -i "s/^export DOTFILES_PROFILE=.*/export DOTFILES_PROFILE=\"$profile\"/" "$BASHRC"
    fi

    success "home-manager active (profile: $profile)"
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

install_updater() {
    section "Login Auto-Updater (systemd user service)"
    local SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
    local SERVICE_SRC="$REPO_DIR/config/systemd/dotfiles-update.service"
    local SERVICE_DEST="$SYSTEMD_USER_DIR/dotfiles-update.service"

    if [[ ! -f "$SERVICE_SRC" ]]; then
        warn "Service unit not found: $SERVICE_SRC — skipping"
        return
    fi

    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$SERVICE_SRC" "$SERVICE_DEST"

    systemctl --user daemon-reload
    systemctl --user enable dotfiles-update.service

    success "dotfiles-update.service enabled (runs updown on login, at most once per 23h)"
    info "Status: systemctl --user status dotfiles-update.service"
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
XDG_MUSIC_DIR="$HOME/Downloads/"
XDG_PICTURES_DIR="$HOME/Downloads/"
XDG_PROJECTS_DIR="$HOME/Downloads/"
XDG_PUBLICSHARE_DIR="$HOME/Downloads/"
XDG_TEMPLATES_DIR="$HOME/Downloads/"
XDG_VIDEOS_DIR="$HOME/Downloads/"
EOF

    # Prevent xdg-user-dirs-update from recreating the default folders
    echo "enabled=False" > "$HOME/.config/user-dirs.conf"

    info "Cleaning up unused default directories (if empty)..."
    for dir in Desktop Music Pictures Public Templates Videos; do
        if [[ -d "$HOME/$dir" ]]; then
            rmdir "$HOME/$dir" 2>/dev/null || true
        fi
    done
    
    mkdir -p "$HOME/Repos" "$HOME/Documents" "$HOME/Downloads"
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
    ln -sf "$REPO_DIR/bin/updown" "$HOME/.local/bin/updown"
    chmod +x "$REPO_DIR/bin/updown"
    chmod +x "$REPO_DIR/bin/update-antigravity"
    success "Symlinked updown → ~/.local/bin/updown"

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

preset_desktop() {
    install_nix
    install_home_manager "desktop"
    install_chrome
    install_yakuake
    install_insync
    install_updater
}

preset_dev() {
    install_nix
    install_home_manager "dev"
    install_chrome
    install_yakuake
    install_insync
    install_antigravity
    install_agy
    install_cursor
    install_ponytail
    install_oc
    install_work_repos
    install_updater
}

# ── TUI selector ─────────────────────────────────────────────────────────────

run_tui() {
    local items=(
        "Google Chrome (Flatpak)"
        "Yakuake (Drop-down Terminal, Flatpak)"
        "Insync (RPM-extracted, no host mutation)"
        "Nix (Determinate Systems OSTree installer)"
        "Home-Manager dev profile (fnm, gh, hadolint, actionlint, yq, jq, rg, fzf, python3, uv)"
        "Home-Manager desktop profile (minimal)"
        "Antigravity Hub (agentic, latest from download page)"
        "agy CLI"
        "Cursor (AppImage)"
        "Ponytail (Lazy Senior Dev rules for agy and Cursor)"
        "OpenShift CLI (oc, GitHub binary)"
        "Clone work repos (SSH key + ~/Repos/)"
        "Login auto-updater (systemd user service, 23h guard)"
    )
    local selected=(0 0 0 0 0 0 0 0 0 0 0 0 0)

    tui_menu items selected "Select components to install (↑↓ Space Enter)"

    # Execute Nix/Home-Manager first so sudo password prompts don't block later
    [[ "${selected[3]}"  == "1" ]] && install_nix
    if [[ "${selected[4]}" == "1" && "${selected[5]}" == "1" ]]; then
        warn "Both dev and desktop home-manager selected — using dev"
        install_home_manager "dev"
    elif [[ "${selected[4]}" == "1" ]]; then
        install_home_manager "dev"
    elif [[ "${selected[5]}" == "1" ]]; then
        install_home_manager "desktop"
    fi

    [[ "${selected[0]}"  == "1" ]] && install_chrome
    [[ "${selected[1]}"  == "1" ]] && install_yakuake
    [[ "${selected[2]}"  == "1" ]] && install_insync
    [[ "${selected[6]}"  == "1" ]] && install_antigravity
    [[ "${selected[7]}"  == "1" ]] && install_agy
    [[ "${selected[8]}"  == "1" ]] && install_cursor
    [[ "${selected[9]}"  == "1" ]] && install_ponytail
    [[ "${selected[10]}" == "1" ]] && install_oc
    [[ "${selected[11]}" == "1" ]] && install_work_repos
    [[ "${selected[12]}" == "1" ]] && install_updater
}


# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
setup.sh — Dotfiles setup for Fedora 44 Kinoite + Nix/Home-Manager

Usage:
  setup.sh [OPTIONS]

Default (no flags): full dev stack, same as --dev.

Options:
  --dev       Full dev stack: Chrome, Yakuake, Insync, Nix/Home-Manager (dev profile),
              Antigravity hub, agy CLI, Cursor, oc, work repos, auto-updater
  --desktop   Desktop essentials: Chrome, Yakuake, Insync, Nix/Home-Manager (desktop
              profile — no dev tools), auto-updater
  --custom    Interactive TUI checkbox picker (select individual components)
  --help      Show this help

Environment variables:
  DOTFILES_DIR        Clone location (default: ~/Repos/dotfiles)
  DOTFILES_REPO       Clone URL (default: GitHub)
  DOTFILES_BRANCH     Branch (default: main)
  DOTFILES_SKIP_PULL  Set to skip git pull on existing clone
  UPDATE              Set UPDATE=1 to force re-download of oc binary
  OC_VERSION          Override oc version tag (default: latest)
  DOTFILES_PROFILE    Active profile written to ~/.bashrc by setup
EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "=== Bootstrapping Dotfiles (Fedora Kinoite + Nix) ==="

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
    --custom)
        run_tui
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
if [[ -d /nix ]]; then
    echo "   Apply Nix packages: home-manager switch --flake $REPO_DIR/config/home-manager#\${DOTFILES_PROFILE:-dev}"
fi
