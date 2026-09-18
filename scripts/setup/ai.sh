#!/usr/bin/env bash
# ai.sh — AI assistant environments, instructions, skills & MCP configurations
#
# Usage:
#   scripts/setup/ai.sh
#   scripts/setup/ai.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# ── AI Instructions & Skills ─────────────────────────────────────────────────

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

    # Global Cursor instructions: user-scoped local plugin only (not per-checkout).
    local CURSOR_USER_DIR="$HOME/.config/Cursor/User"
    if [[ -f "$INSTRUCTIONS_FILE" ]]; then
        info "Configuring Cursor instructions..."
        install_cursor_global_instructions "$INSTRUCTIONS_FILE"
        success "Cursor instructions installed (~/.cursor/plugins/local/dotfiles)"
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

# ── Ponytail Plugin & Rules ──────────────────────────────────────────────────

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
        warn "agy CLI not found. Skipping plugin install."
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

# ── GitHub MCP Server ────────────────────────────────────────────────────────

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

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
Usage:
  scripts/setup/ai.sh [OPTIONS]

Configures AI assistant environments, prompt instructions, agent skills,
Ponytail plugin/rules, and GitHub MCP server.

Options:
  --help, -h   Show this help
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

    echo "=== Configuring AI Assistant Environment ==="
    install_ai_wiring
    install_ponytail
    setup_github_mcp
    success "AI assistant configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
