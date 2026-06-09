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
    
    # Remove old loader lines if present
    # We do a python-based line replacement to make sure we don't mangle other parts
    python3 -c '
import sys
path = sys.argv[1]
with open(path, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # Remove legacy reference
    if "/Documents/1-Personal/Linux/bashrc" in line:
        continue
    # Remove any existing repo bashrc reference to prevent duplicates
    if "Repos/dotfiles/bashrc" in line:
        continue
    new_lines.append(line)

# Append new sourcing block safely
content = "".join(new_lines).rstrip() + "\n\n# Source personal dotfiles configuration\nif [ -f \"$HOME/Repos/dotfiles/bashrc\" ]; then\n    . \"$HOME/Repos/dotfiles/bashrc\"\nfi\n"

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

echo ""
echo "✅ Setup complete! Please run 'source ~/.bashrc' or restart your terminal."
