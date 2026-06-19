#!/bin/bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Repos/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/DerekRoberts/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"

ensure_dotfiles_repo() {
    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        echo "Cloning dotfiles to $DOTFILES_DIR..."
        mkdir -p "$(dirname "$DOTFILES_DIR")"
        git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR"
    elif [[ -z "${DOTFILES_SKIP_PULL:-}" ]]; then
        local current_branch
        current_branch="$(git -C "$DOTFILES_DIR" branch --show-current 2>/dev/null || true)"
        if [[ "$current_branch" == "$DOTFILES_BRANCH" ]]; then
            echo "Updating dotfiles ($DOTFILES_BRANCH)..."
            git -C "$DOTFILES_DIR" pull --ff-only origin "$DOTFILES_BRANCH"
        else
            echo "Note: dotfiles on branch '$current_branch' — skipping pull (not on $DOTFILES_BRANCH)."
        fi
    fi
}

ensure_dotfiles_repo

SETUP_PATH="$(readlink -f "${BASH_SOURCE[0]:-}" 2>/dev/null || true)"
if [[ -z "$SETUP_PATH" ]] || [[ "$SETUP_PATH" != "$DOTFILES_DIR/setup.sh" ]]; then
    exec bash "$DOTFILES_DIR/setup.sh" "$@"
fi

REPO_DIR="$DOTFILES_DIR"
BASHRC="$HOME/.bashrc"

echo "=== Bootstrapping Dotfiles ==="

# 1. Clean up legacy bashrc sourcing and add new loader
if [ -f "$BASHRC" ]; then
    echo "Updating ~/.bashrc sourcing..."
    cp "$BASHRC" "$BASHRC.bak.$(date +%s)"

    python3 - "$BASHRC" "$REPO_DIR" <<'PY'
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
    echo "✓ ~/.bashrc sourcing updated."
fi

# 2. Configure global Git include path
echo "Configuring Git global settings..."
git config --global include.path "$REPO_DIR/gitconfig"
echo "✓ Git include path set to reference $REPO_DIR/gitconfig."

# 3. Symlink bin scripts
echo "Configuring bin scripts..."
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/bin/updown" "$HOME/.local/bin/updown"
chmod +x "$REPO_DIR/bin/updown"
echo "✓ Symlinked updown to ~/.local/bin/updown."

# 4. Symlink Antigravity Configs
echo "Configuring Antigravity..."
ANTIGRAVITY_DIR="$HOME/.config/antigravity"
mkdir -p "$ANTIGRAVITY_DIR"
if [ -f "$ANTIGRAVITY_DIR/instructions.json" ] && [ ! -L "$ANTIGRAVITY_DIR/instructions.json" ]; then
    mv "$ANTIGRAVITY_DIR/instructions.json" "$ANTIGRAVITY_DIR/instructions.json.bak"
    echo "Note: Backed up old instructions.json to instructions.json.bak"
fi
ln -sf "$REPO_DIR/config/antigravity/instructions.json" "$ANTIGRAVITY_DIR/instructions.json"

if [ -f "$HOME/.config/antigravity-flags.conf" ] && [ ! -L "$HOME/.config/antigravity-flags.conf" ]; then
    mv "$HOME/.config/antigravity-flags.conf" "$HOME/.config/antigravity-flags.conf.bak"
    echo "Note: Backed up old antigravity-flags.conf to antigravity-flags.conf.bak"
fi
ln -sf "$REPO_DIR/config/antigravity/antigravity-flags.conf" "$HOME/.config/antigravity-flags.conf"
echo "✓ Symlinked Antigravity config files."

# 5. Symlink VS Code Configs
echo "Configuring VS Code..."
VSCODE_DIR="$HOME/.config/Code/User"
if [ -d "$VSCODE_DIR" ]; then
    if [ -f "$VSCODE_DIR/settings.json" ] && [ ! -L "$VSCODE_DIR/settings.json" ]; then
        mv "$VSCODE_DIR/settings.json" "$VSCODE_DIR/settings.json.bak"
        echo "Note: Backed up old VS Code settings.json to settings.json.bak"
    fi
    ln -sf "$REPO_DIR/config/vscode/settings.json" "$VSCODE_DIR/settings.json"
    echo "✓ Symlinked VS Code settings.json."
else
    echo "Note: VS Code config directory not found at $VSCODE_DIR. Skipping symlink."
fi

# 6. Sync personal instructions into global prompt hub
echo "Syncing personal instructions into global prompt hub..."
bash "$REPO_DIR/scripts/bundle-ai-instructions.sh"

GLOBAL_PROMPT_FILE="$HOME/.config/Code/User/prompts/global.instructions.md"

# 7. Symlink personal tooling to the global prompt hub
echo "Configuring Antigravity global instructions and skills..."
mkdir -p "$HOME/.gemini/config"
mkdir -p "$HOME/.gemini/antigravity"
if [ -L "$HOME/.gemini/GEMINI.md" ] || [ ! -f "$HOME/.gemini/GEMINI.md" ]; then
    ln -sf "$GLOBAL_PROMPT_FILE" "$HOME/.gemini/GEMINI.md"
    echo "✓ Symlinked Antigravity global instructions to $GLOBAL_PROMPT_FILE."
else
    echo "WARNING: ~/.gemini/GEMINI.md is a physical file. Skipping symlink creation."
fi

if [ -L "$HOME/.gemini/config/skills" ] || [ ! -d "$HOME/.gemini/config/skills" ]; then
    ln -sf "$HOME/.agents/skills" "$HOME/.gemini/config/skills"
    echo "✓ Symlinked ~/.gemini/config/skills to ~/.agents/skills."
else
    echo "WARNING: ~/.gemini/config/skills is a physical folder. Skipping symlink creation."
fi

# Remove erroneous circular skills symlink if present (~/.agents/skills/skills -> ~/.gemini/config/skills)
if [ -L "$HOME/.agents/skills/skills" ]; then
    rm -f "$HOME/.agents/skills/skills"
    echo "✓ Removed erroneous ~/.agents/skills/skills circular symlink."
fi

if [ -L "$HOME/.gemini/antigravity/skills" ] || [ ! -d "$HOME/.gemini/antigravity/skills" ]; then
    ln -sf "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills"
    echo "✓ Symlinked ~/.gemini/antigravity/skills to ~/.gemini/config/skills."
else
    echo "WARNING: ~/.gemini/antigravity/skills is a physical folder. Skipping symlink creation."
fi

# 8. Symlink Cursor to the global prompt hub
CURSOR_USER_DIR="$HOME/.config/Cursor/User"
if [ -d "$CURSOR_USER_DIR" ]; then
    echo "Configuring Cursor global instructions..."
    mkdir -p "$CURSOR_USER_DIR/prompts"
    if [ -L "$CURSOR_USER_DIR/prompts/global.instructions.md" ] || [ ! -f "$CURSOR_USER_DIR/prompts/global.instructions.md" ]; then
        ln -sf "$GLOBAL_PROMPT_FILE" "$CURSOR_USER_DIR/prompts/global.instructions.md"
        echo "✓ Symlinked Cursor global instructions to $GLOBAL_PROMPT_FILE."
    else
        echo "WARNING: $CURSOR_USER_DIR/prompts/global.instructions.md is a physical file. Skipping symlink creation."
    fi
else
    echo "Note: Cursor config directory not found at $CURSOR_USER_DIR. Skipping instructions symlink."
fi

# 9. Symlink Ponytail rule into Cursor user rules
PONYTAIL_RULE="$HOME/.copilot/installed-plugins/ponytail/ponytail/.cursor/rules/ponytail.mdc"
if [ -f "$PONYTAIL_RULE" ]; then
    mkdir -p "$HOME/.cursor/rules"
    if [ -L "$HOME/.cursor/rules/ponytail.mdc" ] || [ ! -f "$HOME/.cursor/rules/ponytail.mdc" ]; then
        ln -sf "$PONYTAIL_RULE" "$HOME/.cursor/rules/ponytail.mdc"
        echo "✓ Symlinked Ponytail rule to ~/.cursor/rules/ponytail.mdc."
    else
        echo "WARNING: ~/.cursor/rules/ponytail.mdc is a physical file. Skipping symlink creation."
    fi
else
    echo "Note: Ponytail rule not found at $PONYTAIL_RULE. Skipping Ponytail symlink."
fi

# 10. Remove legacy Kilo symlink if present
if [ -L "$HOME/.copilot.md" ]; then
    rm -f "$HOME/.copilot.md"
    echo "✓ Removed legacy Kilo ~/.copilot.md symlink."
fi

echo ""
echo "✅ Setup complete! Please run 'source ~/.bashrc' or restart your terminal."
