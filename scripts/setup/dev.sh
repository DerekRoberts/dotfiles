#!/usr/bin/env bash
# dev.sh — Developer toolchains, wiring, AI assistant environments & repositories
#
# Usage:
#   scripts/setup/dev.sh
#   scripts/setup/dev.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# ── Git Configuration & Hooks ────────────────────────────────────────────────

wire_git() {
    section "Git Configuration & Hooks"

    info "Configuring Git global settings..."
    command git config --global include.path "$DOTFILES_DIR/config/gitconfig"
    success "Git include path set"

    if [[ -f "$DOTFILES_DIR/scripts/git-setup.sh" ]]; then
        bash "$DOTFILES_DIR/scripts/git-setup.sh"
    fi

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
}

# ── Update Helpers & Cleanup ─────────────────────────────────────────────────

install_update_helpers() {
    section "Developer Utilities & Maintenance Helpers"

    if [[ -f "$DOTFILES_DIR/scripts/update-antigravity.sh" ]]; then
        install -m 755 "$DOTFILES_DIR/scripts/update-antigravity.sh" "$HOME/.local/bin/update-antigravity"
        success "Installed update-antigravity → $HOME/.local/bin/update-antigravity"
    fi

    [[ -L "$HOME/.copilot.md" ]] && rm -f "$HOME/.copilot.md" && info "Removed legacy ~/.copilot.md"
}

# ── AI Assistant Wiring (Antigravity & Cursor) ───────────────────────────────

install_ai_wiring() {
    section "AI Assistant Instructions & Skills"

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

    # Cursor instructions and settings
    local CURSOR_USER_DIR="$HOME/.config/Cursor/User"
    if [[ -f "$INSTRUCTIONS_FILE" ]]; then
        info "Configuring Cursor instructions..."
        mkdir -p "$CURSOR_USER_DIR/prompts"
        rm -f "$CURSOR_USER_DIR/prompts/global.instructions.md"
        cp -f "$INSTRUCTIONS_FILE" "$CURSOR_USER_DIR/prompts/global.instructions.md"
        success "Cursor instructions installed"
    fi

    info "Configuring Cursor default workspace paths..."
    local CURSOR_SETTINGS="$CURSOR_USER_DIR/settings.json"
    mkdir -p "$CURSOR_USER_DIR"
    python3 - "$CURSOR_SETTINGS" << 'PY'
import sys, os, json, re, tempfile

path = sys.argv[1]
dir_path = os.path.dirname(os.path.abspath(path))
os.makedirs(dir_path, exist_ok=True)

data = {}
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()

    # Strip single-line and multi-line comments from JSONC without altering string literals
    def strip_jsonc(text):
        pattern = r'(//[^\n]*)|(/\*[\s\S]*?\*/)|("(?:\\.|[^"\\])*")'
        def replacer(match):
            if match.group(3) is not None:
                return match.group(3)
            return ""
        stripped = re.sub(pattern, replacer, text)
        return re.sub(r',\s*([}\]])', r'\1', stripped)

    cleaned = strip_jsonc(raw).strip()
    if cleaned:
        try:
            data = json.loads(cleaned)
        except Exception as e:
            sys.stderr.write(f"Warning: Failed to parse {path} as JSONC: {e}. Preserving original file.\n")
            sys.exit(0)

data["git.defaultCloneDirectory"] = "~/Repos"
data["files.dialog.defaultPath"] = "~/Repos"

tmp_fd, tmp_path = tempfile.mkstemp(prefix=".settings.tmp.", dir=dir_path)
with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.chmod(tmp_path, 0o644)
os.replace(tmp_path, path)
PY
    success "Cursor default project paths configured"
}

# ── Native Standalone Tools & Toolchains ─────────────────────────────────────

install_native_tools() {
    section "Native Dev Tools & Toolchains"
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

    # Podman socket & docker-compose
    if command -v systemctl &>/dev/null; then
        if systemctl --user is-active podman.socket &>/dev/null; then
            info "podman.socket is already active"
        else
            info "Enabling & starting podman.socket..."
            systemctl --user enable --now podman.socket 2>/dev/null || warn "Failed to enable podman.socket"
        fi
    fi

    if [[ -x "$BIN_DIR/docker-compose" ]]; then
        success "docker-compose already installed"
    else
        info "Downloading docker-compose..."
        local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64"
        local tmp_compose="$BIN_DIR/docker-compose.tmp.$$"
        if curl -fsSL "$compose_url" -o "$tmp_compose"; then
            chmod +x "$tmp_compose"
            mv "$tmp_compose" "$BIN_DIR/docker-compose"
            if command -v restorecon &>/dev/null; then
                restorecon "$BIN_DIR/docker-compose" 2>/dev/null || true
            fi
            success "docker-compose installed"
        else
            rm -f "$tmp_compose"
            warn "Failed to download docker-compose"
        fi
    fi

    # Clean up legacy podman-compose python wrapper script
    if [[ -x "$BIN_DIR/docker-compose" && -f "$BIN_DIR/podman-compose" ]]; then
        rm -f "$BIN_DIR/podman-compose"
    fi

    # ShellCheck CLI
    if ! command -v shellcheck &>/dev/null; then
        info "Downloading shellcheck..."
        local tmp_dir; tmp_dir="$(mktemp -d)"
        local sc_latest; sc_latest=$(curl -sI https://github.com/koalaman/shellcheck/releases/latest | grep -i "^location:" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" || echo "v0.11.0")
        local sc_url="https://github.com/koalaman/shellcheck/releases/download/${sc_latest}/shellcheck-${sc_latest}.linux.x86_64.tar.gz"
        if curl -fsSL "$sc_url" | tar -xz -C "$tmp_dir"; then
            mv "$tmp_dir/shellcheck-${sc_latest}/shellcheck" "$BIN_DIR/shellcheck"
            chmod +x "$BIN_DIR/shellcheck"
            if command -v restorecon &>/dev/null; then
                restorecon "$BIN_DIR/shellcheck" 2>/dev/null || true
            fi
            success "shellcheck installed"
        else
            warn "Failed to download shellcheck ${sc_latest}"
        fi
        rm -rf "$tmp_dir"
    fi

    # actionlint (GitHub Actions workflow linter)
    if ! command -v actionlint &>/dev/null; then
        info "Downloading actionlint..."
        local tmp_dir; tmp_dir="$(mktemp -d)"
        local al_latest; al_latest=$(curl -sI https://github.com/rhysd/actionlint/releases/latest | grep -i "^location:" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" || echo "v1.7.12")
        local al_ver="${al_latest#v}"
        local al_url="https://github.com/rhysd/actionlint/releases/download/${al_latest}/actionlint_${al_ver}_linux_amd64.tar.gz"
        if curl -fsSL "$al_url" | tar -xz -C "$tmp_dir"; then
            mv "$tmp_dir/actionlint" "$BIN_DIR/actionlint"
            chmod +x "$BIN_DIR/actionlint"
            if command -v restorecon &>/dev/null; then
                restorecon "$BIN_DIR/actionlint" 2>/dev/null || true
            fi
            success "actionlint installed"
        else
            warn "Failed to download actionlint ${al_latest}"
        fi
        rm -rf "$tmp_dir"
    fi

    # uv (Fast Python toolchain & package manager)
    if ! command -v uv &>/dev/null; then
        info "Downloading uv..."
        local tmp_dir; tmp_dir="$(mktemp -d)"
        local uv_url="https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-gnu.tar.gz"
        if curl -fsSL "$uv_url" | tar -xz -C "$tmp_dir"; then
            mv "$tmp_dir/uv-x86_64-unknown-linux-gnu/uv" "$BIN_DIR/uv"
            mv "$tmp_dir/uv-x86_64-unknown-linux-gnu/uvx" "$BIN_DIR/uvx"
            chmod +x "$BIN_DIR/uv" "$BIN_DIR/uvx"
            if command -v restorecon &>/dev/null; then
                restorecon "$BIN_DIR/uv" "$BIN_DIR/uvx" 2>/dev/null || true
            fi
            success "uv and uvx installed"
        else
            warn "Failed to download uv"
        fi
        rm -rf "$tmp_dir"
    fi

    # nvm & Node LTS
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | PROFILE=/dev/null bash
        success "nvm installed"
    fi

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

# ── AI Tools & Editors ───────────────────────────────────────────────────────

install_antigravity() {
    section "Antigravity Hub"
    local UPDATER="$DOTFILES_DIR/scripts/update-antigravity.sh"
    if [[ ! -f "$UPDATER" ]]; then
        warn "scripts/update-antigravity.sh not found — skipping"
        return
    fi
    bash "$UPDATER"

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

    if command -v restorecon &>/dev/null; then
        restorecon "$CURSOR_BIN" 2>/dev/null || true
    fi

    local STAMP_FILE="$HOME/.local/share/dotfiles/cursor.url"
    mkdir -p "$(dirname "$STAMP_FILE")"
    echo "$CURSOR_URL" > "$STAMP_FILE"

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

install_oc() {
    section "OpenShift CLI (oc)"
    bash "$DOTFILES_DIR/scripts/bootstrap-tools.sh"
}

install_repos() {
    section "Repositories"
    bash "$DOTFILES_DIR/scripts/clone-repos.sh" || warn "Some repositories could not be cloned. Run 'scripts/clone-repos.sh' once your SSH key is authorized on GitHub."
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
Usage:
  scripts/setup/dev.sh [OPTIONS]

Options:
  --help, -h  Show this help
EOF
}

main() {
    case "${1:-}" in
        --help|-h)
            usage
            exit 0
            ;;
        "")
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac

    echo "=== Configuring Developer Stack ==="
    wire_git
    install_update_helpers
    install_ai_wiring
    install_native_tools
    install_antigravity
    install_agy
    install_cursor
    install_ponytail
    install_oc
    install_repos
    success "Developer stack configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
