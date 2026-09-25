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
        local tmp_file
        tmp_file="$(mktemp "$HOME/.gemini/GEMINI.md.XXXXXX")"
        cp -f "$INSTRUCTIONS_FILE" "$tmp_file"
        chmod 644 "$tmp_file"
        mv -f "$tmp_file" "$HOME/.gemini/GEMINI.md"
        success "Installed ~/.gemini/GEMINI.md"
    fi

    if [[ -d "$DOTFILES_DIR/config/skills" ]]; then
        if command -v git &>/dev/null && [[ -f "$DOTFILES_DIR/.gitmodules" ]] && git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
            git -C "$DOTFILES_DIR" submodule update --init --recursive 2>/dev/null || true
        fi

        for skill_dir in "$DOTFILES_DIR/config/skills"/*; do
            [[ -d "$skill_dir" ]] || continue
            if [[ -z "$(ls -A "$skill_dir" 2>/dev/null)" ]]; then
                warn "Skill directory $(basename "$skill_dir") is empty — skipping"
                continue
            fi
            local skill_name; skill_name="$(basename "$skill_dir")"
            local target_dir="$HOME/.agents/skills/$skill_name"
            local tmp_dir
            tmp_dir="$(mktemp -d "$HOME/.agents/skills/.${skill_name}.XXXXXX")"
            if cp -aT "$skill_dir" "$tmp_dir"; then
                rm -rf "$target_dir"
                mv -f "$tmp_dir" "$target_dir"
            else
                rm -rf "$tmp_dir"
                warn "Failed to copy skill $skill_name"
            fi
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
    # Parse JSONC string-aware (preserving URLs/strings with //), merge settings, and write back formatted JSON
    local tmp_file
    tmp_file="$(mktemp "${CURSOR_SETTINGS%/*}/settings.XXXXXX")"
    if python3 -c '
import json, re, sys

settings_path, out_path = sys.argv[1], sys.argv[2]
try:
    with open(settings_path, "r", encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    text = "{}"

# Strip comments (single-line and multi-line) while preserving quoted strings
text = re.sub(r"(\"(?:\\.|[^\"\\])*\")|//[^\r\n]*|/\*[\s\S]*?\*/", lambda m: m.group(1) or "", text)
# Strip trailing commas before closing braces/brackets while preserving quoted strings
text = re.sub(r"(\"(?:\\.|[^\"\\])*\")|,\s*([\]}])", lambda m: m.group(1) or m.group(2), text)

data = json.loads(text) if text.strip() else {}
data.update({
    "git.defaultCloneDirectory": "~/Repos",
    "files.dialog.defaultPath": "~/Repos",
    "update.mode": "none"
})

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
' "$CURSOR_SETTINGS" "$tmp_file"; then
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

    # Pinned to a commit: this file becomes standing instructions for every
    # agent session, so it must not change under us when upstream moves main.
    # Bump PONYTAIL_REF deliberately after reading the diff.
    local PONYTAIL_REF="2ed6c52c9d7e5e56942508591085fd45dea277d3"

    info "Configuring Ponytail for Cursor..."
    local CURSOR_RULES_DIR="$HOME/.cursor/rules"
    mkdir -p "$CURSOR_RULES_DIR"
    if [[ -f "$CURSOR_RULES_DIR/ponytail.mdc" ]]; then
        success "Cursor rule already present"
    else
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
            local tmp_clone
            tmp_clone="$(mktemp -d "${TMPDIR:-/tmp}/ponytail.XXXXXX")"
            if git clone --quiet https://github.com/DietrichGebert/ponytail "$tmp_clone" \
                && git -C "$tmp_clone" checkout --quiet --detach "$PONYTAIL_REF" \
                && "$AGY_BIN" plugin install "$tmp_clone" 2>/dev/null; then
                success "agy plugin installed"
            else
                warn "agy plugin install failed (network issue or repo error)"
            fi
            rm -rf "$tmp_clone"
        fi
    fi
}

# ── GitHub MCP Server ────────────────────────────────────────────────────────

write_github_mcp_config() {
    local config_file="$1"
    local gh_token="$2"
    local mcp_pkg="@modelcontextprotocol/server-github@2025.4.8"

    mkdir -p "$(dirname "$config_file")"
    if [[ ! -s "$config_file" ]]; then
        echo '{"mcpServers": {}}' > "$config_file"
    fi

    local tmp_file
    tmp_file="$(mktemp "$(dirname "$config_file")/mcp.XXXXXX")"

    if jq --arg token "$gh_token" --arg pkg "$mcp_pkg" \
        '.mcpServers.github = {"command": "npx", "args": ["-y", $pkg], "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": $token}}' \
        "$config_file" > "$tmp_file"; then
        chmod 600 "$tmp_file"
        mv -f "$tmp_file" "$config_file"
    else
        rm -f "$tmp_file"
        warn "Failed to write GitHub MCP config"
        return 1
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
    if write_github_mcp_config "$config_file" "$gh_token"; then
        success "GitHub MCP Server configured at $config_file"
    fi
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
