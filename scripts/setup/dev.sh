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

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# ── Git Configuration & Hooks ────────────────────────────────────────────────

wire_git() {
    section "Git Configuration & Hooks"

    info "Configuring Git global settings..."
    local installed_gitconfig="${DOTFILES_USER_CONFIG:-$HOME/.config/dotfiles}/gitconfig"
    if [[ -f "$DOTFILES_DIR/config/gitconfig" ]]; then
        install_copy "$DOTFILES_DIR/config/gitconfig" "$installed_gitconfig" 644
        command git config --global include.path "$installed_gitconfig"
        success "Git include path set → $installed_gitconfig"
    fi

    if [[ -f "$DOTFILES_DIR/scripts/git-setup.sh" ]]; then
        bash "$DOTFILES_DIR/scripts/git-setup.sh"
    fi

    local HOOKS_SRC_DIR="$DOTFILES_DIR/config/hooks"
    local HOOKS_DEST_DIR="$HOME/.githooks"
    if [[ -d "$HOOKS_SRC_DIR" ]]; then
        info "Installing global git hooks..."
        if [[ -L "$HOOKS_DEST_DIR" ]]; then
            rm -f "$HOOKS_DEST_DIR"
        fi
        mkdir -p "$HOOKS_DEST_DIR"
        for hook_file in "$HOOKS_SRC_DIR"/*; do
            [[ -f "$hook_file" ]] || continue
            local hook_name; hook_name="$(basename "$hook_file")"
            install_copy "$hook_file" "$HOOKS_DEST_DIR/$hook_name"
        done
        success "Global git hooks installed → $HOOKS_DEST_DIR"
    fi
}

# ── Update Helpers & Cleanup ─────────────────────────────────────────────────

install_update_helpers() {
    section "Developer Utilities & Maintenance Helpers"

    if [[ -f "$DOTFILES_DIR/scripts/update-antigravity.sh" ]]; then
        install_copy "$DOTFILES_DIR/scripts/update-antigravity.sh" "$HOME/.local/bin/update-antigravity"
        success "Installed update-antigravity → $HOME/.local/bin/update-antigravity"
    fi

    if [[ -L "$HOME/.copilot.md" ]]; then
        rm -f "$HOME/.copilot.md"
        info "Removed legacy ~/.copilot.md"
    fi
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

    # Both Antigravity lookup paths point at the one real skills directory.
    # Link directly rather than chaining, so neither can become a cycle.
    local link
    for link in "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills"; do
        if [[ -d "$link" && ! -L "$link" ]]; then
            warn "$link is a real directory — leaving it alone"
            continue
        fi
        ln -sfn "$HOME/.agents/skills" "$link"
    done

    # Cursor user-rule files: ~/.cursor/rules (global, this machine). Do not
    # write into repositories.
    local CURSOR_USER_DIR="$HOME/.config/Cursor/User"
    if [[ -f "$INSTRUCTIONS_FILE" ]]; then
        info "Configuring Cursor instructions..."
        mkdir -p "$CURSOR_USER_DIR/prompts"
        rm -f "$CURSOR_USER_DIR/prompts/global.instructions.md"
        cp -f "$INSTRUCTIONS_FILE" "$CURSOR_USER_DIR/prompts/global.instructions.md"
        write_cursor_dotfiles_mdc "$INSTRUCTIONS_FILE"
        success "Cursor instructions installed (~/.cursor/rules/dotfiles.mdc)"
    fi

    info "Configuring Cursor default workspace paths and update settings..."
    local CURSOR_SETTINGS="$CURSOR_USER_DIR/settings.json"
    mkdir -p "$CURSOR_USER_DIR"
    if [[ ! -s "$CURSOR_SETTINGS" ]]; then
        echo "{}" > "$CURSOR_SETTINGS"
    fi
    # Strip comments loosely and merge with jq, write back standard JSON
    local tmp_file
    tmp_file="$(mktemp "${CURSOR_SETTINGS%/*}/settings.XXXXXX")"
    if sed -E 's|//.*||g; s|/\*.*\*/||g' "$CURSOR_SETTINGS" | \
        jq '. + {"git.defaultCloneDirectory": "~/Repos", "files.dialog.defaultPath": "~/Repos", "update.mode": "none"}' > "$tmp_file"; then
        mv -f "$tmp_file" "$CURSOR_SETTINGS"
        success "Cursor default project paths and update settings configured"
    else
        rm -f "$tmp_file"
        warn "Failed to update Cursor settings"
        return 1
    fi
}

# ── Native Standalone Tools & Toolchains ─────────────────────────────────────
#
# EXPECTED_SHA256, if set by a caller, is checked by fetch_tarball_bins before
# extraction. Only oc can use it: GitHub releases here publish no checksums.

# curl flags for tag lookups and binary downloads (timeouts keep updown from hanging)
GH_CURL_META=(--fail --silent --show-error --location --connect-timeout 10 --max-time 20 --retry 2)
GH_CURL_FILE=(--fail --silent --show-error --location --connect-timeout 10 --max-time 120 --retry 2)

asset_name_from_pattern() {
    local pattern="$1" tag="$2"
    local ver="${tag#v}"
    local asset="${pattern//\{tag\}/$tag}"
    printf '%s\n' "${asset//\{ver\}/$ver}"
}

is_tarball_asset() {
    [[ "$1" =~ \.(tar\.gz|tgz)$ ]]
}

# Final URL after /releases/latest redirect, e.g. .../releases/tag/v2.98.0
tag_from_release_url() {
    local url="$1"
    local tag="${url##*/tag/}"
    tag="${tag%%[?#]*}"
    tag="${tag//$'\r'/}"
    printf '%s\n' "$tag"
}

gh_latest_tag() {
    local repo="$1" url tag
    url="$(curl "${GH_CURL_META[@]}" -I -o /dev/null -w '%{url_effective}' \
        "https://github.com/${repo}/releases/latest")" || return 1
    tag="$(tag_from_release_url "$url")"
    [[ -n "$tag" && "$tag" != "$url" ]] || return 1
    printf '%s\n' "$tag"
}

install_bins_from_dir() {
    local src_dir="$1"
    shift
    local b found
    for b in "$@"; do
        found="$(find "$src_dir" -type f -name "$b" -print -quit)"
        if [[ -z "$found" ]]; then
            warn "Binary '$b' not found in archive"
            return 1
        fi
        chmod +x "$found"
        mv -f "$found" "$BIN_DIR/$b"
        if command -v restorecon &>/dev/null; then
            restorecon "$BIN_DIR/$b" 2>/dev/null || true
        fi
    done
}

bins_ready() {
    local b
    for b in "$@"; do
        [[ -x "$BIN_DIR/$b" ]] || return 1
    done
    return 0
}

fetch_gh_release() {
    local name="$1"
    local repo="$2"
    local asset_pattern="$3"
    local bin_names="${4:-$name}"
    local stamp_file="$HOME/.local/share/dotfiles/${name}.tag"
    local update="${UPDATE:-0}"
    local -a bins
    read -ra bins <<< "$bin_names"

    BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
    mkdir -p "$BIN_DIR"

    if bins_ready "${bins[@]}" && [[ -f "$stamp_file" && "$update" -eq 0 ]]; then
        return 0
    fi

    local tag
    if ! tag="$(gh_latest_tag "$repo")"; then
        warn "Could not resolve latest release tag for $repo"
        return 1
    fi

    if bins_ready "${bins[@]}" && [[ -f "$stamp_file" && "$(cat "$stamp_file")" == "$tag" ]]; then
        success "$name is up to date ($tag)"
        return 0
    fi

    info "Downloading $name ($tag)..."
    local asset_name url rc=0
    asset_name="$(asset_name_from_pattern "$asset_pattern" "$tag")"
    url="https://github.com/$repo/releases/download/${tag}/${asset_name}"

    if is_tarball_asset "$asset_name"; then
        fetch_tarball_bins "$url" "${bins[@]}" || rc=1
    else
        fetch_raw_bin "$url" "$name" || rc=1
    fi

    if [[ "$rc" -eq 0 ]]; then
        mkdir -p "$(dirname "$stamp_file")"
        echo "$tag" > "$stamp_file"
        success "$name installed ($tag)"
    fi
    return "$rc"
}

# Download a tarball to disk, refuse it if its members could escape the
# extraction directory, then install the named binaries out of it.
fetch_tarball_bins() {
    local url="$1"; shift
    local tmp_dir tmp_file rc=0
    tmp_dir="$(mktemp -d "${BIN_DIR}/.tmpdir.XXXXXX")"
    tmp_file="$tmp_dir/asset.tar.gz"

    if ! curl "${GH_CURL_FILE[@]}" "$url" -o "$tmp_file"; then
        warn "Failed to download $url"
        rc=1
    elif [[ -n "${EXPECTED_SHA256:-}" ]] && ! verify_sha256 "$tmp_file" "$EXPECTED_SHA256"; then
        warn "Checksum mismatch for $url — refusing to install"
        rc=1
    elif ! tar -xzf "$tmp_file" -C "$tmp_dir" --no-same-owner; then
        warn "Failed to extract $url"
        rc=1
    elif ! install_bins_from_dir "$tmp_dir" "$@"; then
        rc=1
    fi

    rm -rf "$tmp_dir"
    return "$rc"
}

# Download a bare binary to a temp file and swap it into place, so an
# interrupted download can't leave a truncated executable on PATH.
fetch_raw_bin() {
    local url="$1" name="$2"
    local tmp_dir rc=0
    tmp_dir="$(mktemp -d "${BIN_DIR}/.tmpdir.XXXXXX")"

    if ! curl "${GH_CURL_FILE[@]}" "$url" -o "$tmp_dir/$name"; then
        warn "Failed to download $url"
        rc=1
    else
        chmod +x "$tmp_dir/$name"
        mv -f "$tmp_dir/$name" "$BIN_DIR/$name"
        if command -v restorecon &>/dev/null; then
            restorecon "$BIN_DIR/$name" 2>/dev/null || true
        fi
    fi

    rm -rf "$tmp_dir"
    return "$rc"
}

# oc ships from Red Hat's mirror rather than a GitHub release, so it tracks the
# version in release.txt instead of a tag.
OC_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"

install_oc() {
    local asset="openshift-client-linux.tar.gz"
    local target="${OC_VERSION:-latest}"
    if [[ "$target" == "latest" ]]; then
        # Fetch into a variable rather than piping: an awk that exits on the
        # first match closes the pipe early and trips curl under pipefail.
        local release_txt
        release_txt="$(curl "${GH_CURL_META[@]}" "$OC_MIRROR/latest/release.txt")" || release_txt=""
        # release.txt indents the field: "  Version:  4.22.10"
        target="$(awk '/^[[:space:]]*Version:/ {print $2; exit}' <<< "$release_txt")"
    fi
    if [[ -z "$target" ]]; then
        warn "Could not resolve latest oc version"
        return 1
    fi

    local current
    current="$("$BIN_DIR/oc" version --client 2>/dev/null | awk '/Client Version:/ {print $3; exit}' || true)"
    if [[ "${UPDATE:-0}" -eq 0 && "$current" == "$target" ]]; then
        success "oc is up to date ($current)"
        return 0
    fi

    # Unlike every other download here, Red Hat publishes per-release checksums.
    local sums EXPECTED_SHA256
    sums="$(curl "${GH_CURL_META[@]}" "$OC_MIRROR/${target}/sha256sum.txt")" || sums=""
    EXPECTED_SHA256="$(awk -v a="$asset" '$2 == a {print $1; exit}' <<< "$sums")"
    if [[ -z "$EXPECTED_SHA256" ]]; then
        warn "No published checksum for oc $asset ($target) — refusing to install"
        return 1
    fi

    info "Downloading oc ($target)..."
    fetch_tarball_bins "$OC_MIRROR/${target}/${asset}" oc || return 1
    success "oc installed ($target, checksum verified)"
}

install_cli_tools() {
    info "Installing standalone binaries..."
    BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
    mkdir -p "$BIN_DIR"
    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        export PATH="${BIN_DIR}:${PATH}"
    fi

    local failed=0
    fetch_gh_release "jq"             "jqlang/jq"           "jq-linux-amd64"                          || failed=1
    fetch_gh_release "gh"             "cli/cli"             "gh_{ver}_linux_amd64.tar.gz"             || failed=1
    fetch_gh_release "gitleaks"       "gitleaks/gitleaks"   "gitleaks_{ver}_linux_x64.tar.gz"         || failed=1
    fetch_gh_release "docker-compose" "docker/compose"      "docker-compose-linux-x86_64"             || failed=1
    fetch_gh_release "shellcheck"     "koalaman/shellcheck" "shellcheck-{tag}.linux.x86_64.tar.gz"    || failed=1
    fetch_gh_release "actionlint"     "rhysd/actionlint"    "actionlint_{ver}_linux_amd64.tar.gz"     || failed=1
    fetch_gh_release "uv"             "astral-sh/uv"        "uv-x86_64-unknown-linux-gnu.tar.gz" "uv uvx" || failed=1
    install_oc || failed=1

    # Clean up legacy podman-compose python wrapper script
    if [[ -x "$BIN_DIR/docker-compose" && -f "$BIN_DIR/podman-compose" ]]; then
        rm -f "$BIN_DIR/podman-compose"
    fi
    return "$failed"
}


install_native_tools() {
    section "Native Dev Tools & Toolchains"
    install_cli_tools || true

    # Podman socket
    if command -v systemctl &>/dev/null; then
        if systemctl --user is-active podman.socket &>/dev/null; then
            info "podman.socket is already active"
        else
            info "Enabling & starting podman.socket..."
            systemctl --user enable --now podman.socket 2>/dev/null || warn "Failed to enable podman.socket"
        fi
    fi

    # nvm & Node LTS
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        info "Installing nvm..."
        local nvm_tag
        nvm_tag="$(gh_latest_tag "nvm-sh/nvm" || true)"
        nvm_tag="${nvm_tag:-v0.40.1}"
        curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
            -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_tag}/install.sh" | PROFILE=/dev/null bash
        success "nvm installed ($nvm_tag)"
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
    # ponytail: upstream publishes no versioned installer or checksum, so this
    # trusts TLS and Google's origin alone. Pin it if they ever ship a tag.
    curl -fsSL https://antigravity.google/cli/install.sh | bash

    if command -v restorecon &>/dev/null && [[ -f "$AGY_BIN" ]]; then
        restorecon "$AGY_BIN" 2>/dev/null || true
    fi
    success "agy CLI installed"
}

install_kilo() {
    section "Kilo Code CLI"
    if ! load_nvm; then
        warn "nvm/npm not available — skipping Kilo CLI"
        return 0
    fi
    local update="${UPDATE:-0}"
    if [[ "$update" -eq 0 ]] && kilo_cli_installed; then
        success "Kilo CLI already installed: $(kilo --version 2>/dev/null || echo unknown)"
        return 0
    fi
    info "Installing @kilocode/cli via nvm npm (userspace, not /usr)..."
    install_kilo_cli_pkg
    success "Kilo CLI installed: $(kilo --version 2>/dev/null || echo ok)"
}

install_cursor() {
    section "Cursor (AppImage)"
    local BIN_DIR="$HOME/.local/bin"
    local CURSOR_BIN="$BIN_DIR/cursor.AppImage"
    local APPS_DIR="$HOME/.local/share/applications"

    local STAMP_FILE="$HOME/.local/share/dotfiles/cursor.url"
    local update="${UPDATE:-0}"

    if [[ -x "$CURSOR_BIN" && -f "$STAMP_FILE" && "$update" -eq 0 ]]; then
        success "Cursor already installed"
    else
        info "Fetching latest Cursor AppImage URL..."
        local CURSOR_URL
        if ! CURSOR_URL="$(cursor_latest_url)"; then
            warn "Cursor download URL missing or outside $CURSOR_URL_PREFIX — skipping"
            warn "Manual download: https://www.cursor.com/downloads"
            return 1
        fi

        if [[ -x "$CURSOR_BIN" && -f "$STAMP_FILE" && "$(<"$STAMP_FILE")" == "$CURSOR_URL" ]]; then
            success "Cursor is up to date"
        else
            info "Downloading Cursor: $CURSOR_URL"
            mkdir -p "$BIN_DIR"
            local tmp_bin
            tmp_bin="$(mktemp "${CURSOR_BIN}.XXXXXX")"
            if ! curl -fsSL "$CURSOR_URL" -o "$tmp_bin" \
                || ! chmod +x "$tmp_bin" \
                || ! mv -f "$tmp_bin" "$CURSOR_BIN"; then
                rm -f "$tmp_bin"
                warn "Failed to download or stage Cursor AppImage"
                return 1
            fi

            if command -v restorecon &>/dev/null; then
                restorecon "$CURSOR_BIN" 2>/dev/null || true
            fi

            mkdir -p "$(dirname "$STAMP_FILE")"
            echo "$CURSOR_URL" > "$STAMP_FILE"
            success "Cursor AppImage installed to $CURSOR_BIN"
        fi
    fi

    # Always ensure desktop launcher and CLI wrapper are configured idempotently
    mkdir -p "$APPS_DIR" "$BIN_DIR"
    # --appimage-extract-and-run: Kinoite/Fedora 44 omits libfuse.so.2 (FUSE 2).
    # --no-sandbox: AppImage cannot use Chromium's SUID sandbox on Kinoite.
    cat > "$APPS_DIR/cursor.desktop" << DESKTOP
[Desktop Entry]
Name=Cursor
Comment=AI-first code editor
Exec=$CURSOR_BIN --appimage-extract-and-run --no-sandbox %F
Icon=cursor
Terminal=false
Type=Application
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupNotify=true
StartupWMClass=Cursor
DESKTOP

    cat > "$BIN_DIR/cursor" << 'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.local/bin/cursor.AppImage" --appimage-extract-and-run --no-sandbox "$@"
WRAPPER
    chmod +x "$BIN_DIR/cursor"

    success "Cursor desktop launcher and CLI wrapper configured"
}

install_ponytail() {
    section "Ponytail (Lazy Senior Dev)"

    info "Configuring Ponytail for Cursor..."
    local CURSOR_RULES_DIR="$HOME/.cursor/rules"
    mkdir -p "$CURSOR_RULES_DIR"
    if [[ -f "$CURSOR_RULES_DIR/ponytail.mdc" ]]; then
        success "Cursor rule already present"
    else
        # Pinned to a commit: this file becomes standing instructions for every
        # agent session, so it must not change under us when upstream moves main.
        # Bump PONYTAIL_REF deliberately after reading the diff.
        local PONYTAIL_REF="2ed6c52c9d7e5e56942508591085fd45dea277d3"
        local PONYTAIL_URL="https://raw.githubusercontent.com/DietrichGebert/ponytail/${PONYTAIL_REF}/.cursor/rules/ponytail.mdc"
        if curl -fsSL "$PONYTAIL_URL" -o "$CURSOR_RULES_DIR/ponytail.mdc.tmp" \
            && [[ -s "$CURSOR_RULES_DIR/ponytail.mdc.tmp" ]]; then
            mv -f "$CURSOR_RULES_DIR/ponytail.mdc.tmp" "$CURSOR_RULES_DIR/ponytail.mdc"
            success "Cursor rule downloaded to $CURSOR_RULES_DIR/ponytail.mdc"
        else
            rm -f "$CURSOR_RULES_DIR/ponytail.mdc.tmp"
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

write_github_mcp_config() {
    local config_file="$1"
    local gh_token="$2"

    mkdir -p "$(dirname "$config_file")"
    if [[ ! -s "$config_file" ]]; then
        echo '{"mcpServers": {}}' > "$config_file"
    fi

    local tmp_file
    tmp_file="$(mktemp "$(dirname "$config_file")/mcp.XXXXXX")"
    
    if jq --arg token "$gh_token" '.mcpServers.github = {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": $token}}' "$config_file" > "$tmp_file"; then
        chmod 600 "$tmp_file"
        mv -f "$tmp_file" "$config_file"
    else
        rm -f "$tmp_file"
        warn "Failed to write GitHub MCP config"
    fi
}

setup_github_mcp() {
    section "GitHub MCP Server (Antigravity / Gemini)"

    local config_dir="$HOME/.gemini/config"
    local config_file="$config_dir/mcp_config.json"

    if ! command -v gh &>/dev/null; then
        warn "GitHub CLI ('gh') is not installed. Skipping GitHub MCP configuration."
        return 0
    fi

    local gh_token
    gh_token="$(unset GITHUB_TOKEN; gh auth token 2>/dev/null || true)"

    if [[ -z "$gh_token" ]]; then
        warn "No active GitHub CLI login found. Run 'gh auth login' before configuring GitHub MCP."
        return 0
    fi

    mkdir -p "$config_dir"
    write_github_mcp_config "$config_file" "$gh_token"
    success "GitHub MCP Server configured at $config_file"
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
  --tools, -t  Install/update standalone CLI tools only (jq, gh, gitleaks,
               docker-compose, shellcheck, actionlint, uv). Skips nvm/podman.
  --help, -h   Show this help

Environment:
  UPDATE=1     Re-check upstream for newer CLI tool tags and Cursor even if binaries exist
EOF
}

main() {
    case "${1:-}" in
        --help|-h)
            usage
            exit 0
            ;;
        --tools|-t)
            section "Standalone CLI Tools"
            install_cli_tools
            exit $?
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
    install_kilo
    install_cursor
    install_ponytail
    setup_github_mcp
    install_repos
    rebuild_ksycoca
    success "Developer stack configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
