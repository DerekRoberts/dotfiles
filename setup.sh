#!/bin/bash
set -euo pipefail

REPO_DIR="$HOME/Repos/dotfiles"
BASHRC="$HOME/.bashrc"
LEGACY_SOURCE=". /home/derek/Documents/1-Personal/Linux/bashrc"
NEW_SOURCE="if [ -f \"\$HOME/Repos/dotfiles/bashrc\" ]; then . \"\$HOME/Repos/dotfiles/bashrc\"; fi"

echo "=== Bootstrapping Dotfiles ==="

# 1. Clean up legacy bashrc sourcing and add new loader
if [ -f "$BASHRC" ]; then
    echo "Updating ~/.bashrc sourcing..."
    # Create backup
    cp "$BASHRC" "$BASHRC.bak.$(date +%s)"
    
    # Use python regex substitution to safely strip old blocks and avoid leaving orphaned 'fi' lines
    python3 -c '
import sys, re
path = sys.argv[1]
with open(path, "r") as f:
    content = f.read()

# 1. Strip the legacy personal Documents bashrc if present
content = re.sub(r".*/Documents/1-Personal/Linux/bashrc.*\n*", "", content)

# 2. Strip any existing repo dotfiles block (including the if/then/fi)
content = re.sub(r"# Source personal dotfiles configuration\nif \[ -f \"\$HOME/Repos/dotfiles/bashrc\" \]; then\n    \. \"\$HOME/Repos/dotfiles/bashrc\"\nfi\n*", "", content)

# 3. Remove any orphaned fi lines left behind by the old buggy script
content = re.sub(r"# Source personal dotfiles configuration\nfi\n*", "", content)

# Write back with the clean block appended
content = content.rstrip() + "\n\n# Source personal dotfiles configuration\nif [ -f \"$HOME/Repos/dotfiles/bashrc\" ]; then\n    . \"$HOME/Repos/dotfiles/bashrc\"\nfi\n"
with open(path, "w") as f:
    f.write(content)
' "$BASHRC"
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

# 6. Symlink Antigravity global instructions & skills to Copilot paths
echo "Configuring Antigravity global instructions and skills..."
mkdir -p "$HOME/.gemini/config"
mkdir -p "$HOME/.gemini/antigravity"

GLOBAL_PROMPT_FILE="$HOME/.config/Code/User/prompts/global.instructions.md"
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

if [ -L "$HOME/.gemini/antigravity/skills" ] || [ ! -d "$HOME/.gemini/antigravity/skills" ]; then
    ln -sf "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills"
    echo "✓ Symlinked ~/.gemini/antigravity/skills to ~/.gemini/config/skills."
else
    echo "WARNING: ~/.gemini/antigravity/skills is a physical folder. Skipping symlink creation."
fi

# 7. Symlink Cursor global instructions to Copilot paths
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

echo ""
echo "✅ Setup complete! Please run 'source ~/.bashrc' or restart your terminal."
