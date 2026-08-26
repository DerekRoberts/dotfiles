#!/bin/bash
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash
#   setup.sh --dev      # Full dev stack, non-interactive (default)
#   setup.sh --desktop  # Desktop essentials (Chrome + VLC + Insync minimal)
#   setup.sh --help     # Show usage

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

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Usage:
  setup.sh [OPTIONS]

Default (no flags): full dev stack, same as --dev.

Options:
  --dev       Full developer stack: Node LTS, CLI tools, Chrome, VLC, Yakuake, Insync,
              Antigravity hub, agy CLI, Cursor, oc, Ponytail, GitHub MCP, and repositories
  --desktop   Minimal desktop essentials: Chrome, VLC, and Insync
  --help, -h  Show this help

Environment variables:
  UPDATE              Set UPDATE=1 to re-check GitHub CLI tools and oc
  OC_VERSION          Override oc version tag (default: latest)
EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

PROFILE="dev"
case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --desktop)
        PROFILE="desktop"
        ;;
    --dev|"")
        PROFILE="dev"
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
esac

echo "=== Bootstrapping Dotfiles (Fedora Kinoite) ==="

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# Insync is the only privileged step. Skip the password prompt unless we still
# need to layer it or a newer RPM is in the yum repo.
if insync_needs_root; then
    echo "Prompting for sudo to layer or update Insync via rpm-ostree..."
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# 1. Core system and shell profile wiring
bash "$DOTFILES_DIR/scripts/setup/core.sh" "--$PROFILE"

# 2. Desktop layout, system tray, natural scrolling & notifications
bash "$DOTFILES_DIR/scripts/setup/desktop.sh" "--$PROFILE"

# 3. Application installers
bash "$DOTFILES_DIR/scripts/setup/apps.sh" "--$PROFILE"

# 4. Developer toolchains, AI assistants & repositories
if [[ "$PROFILE" == "dev" ]]; then
    echo "Profile: dev (full stack)"
    bash "$DOTFILES_DIR/scripts/setup/dev.sh"
else
    echo "Profile: desktop (essentials)"
fi

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

if command -v systemctl &>/dev/null && systemctl --user is-active plasma-plasmashell &>/dev/null; then
    systemctl --user restart plasma-plasmashell >/dev/null 2>&1 || true
fi

echo ""
echo "✅ Setup complete!"
echo "   Run: source ~/.bashrc   (or restart terminal)"
if [[ -f "$DOTFILES_DIR/scripts/tpm-enroll.sh" ]]; then
    echo "   Optional: To enable TPM 2.0 LUKS auto-unlock, run:"
    echo "             $DOTFILES_DIR/scripts/tpm-enroll.sh"
fi
