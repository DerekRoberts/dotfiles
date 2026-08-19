#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${ANTIGRAVITY_INSTALL_DIR:-$HOME/.local/bin/antigravity}"

if [ -L "$INSTALL_DIR" ]; then
    echo "Error: Install directory '$INSTALL_DIR' is a symbolic link." >&2
    exit 1
fi

CANONICAL_INSTALL_DIR=$(realpath -m "$INSTALL_DIR")

if [ -L "$CANONICAL_INSTALL_DIR" ] || echo "$CANONICAL_INSTALL_DIR" | grep -qE '^/(usr|etc|bin|sbin|lib|root|boot|dev|sys|proc)($|/)'; then
    echo "Error: Install directory '$INSTALL_DIR' is unsafe or restricted." >&2
    exit 1
fi
INSTALL_DIR="$CANONICAL_INSTALL_DIR"

DOWNLOAD_PAGE="https://antigravity.google/download"
CURRENT_VER=$(jq -r '.version' "$INSTALL_DIR/resources/app/package.json" 2>/dev/null || echo "Not Installed / Unknown")
echo "Current Antigravity installation version: $CURRENT_VER"

TARBALL_PATH=""
IS_TEMP_FILE=false

if [ -n "${1:-}" ] && [ -f "$1" ]; then
    echo "Using provided local tarball: $1"
    TARBALL_PATH=$(realpath "$1")
else
    echo "Fetching latest Linux x64 download URL from $DOWNLOAD_PAGE..."
    DOWNLOAD_URL=$(curl -sL --compressed --max-redirs 5 "$DOWNLOAD_PAGE" | grep -oE 'https://storage\.googleapis\.com/antigravity-public/antigravity-hub/[^"]+/linux-x64/Antigravity\.tar\.gz' | head -n 1) || DOWNLOAD_URL=""

    if [ -z "$DOWNLOAD_URL" ] || ! echo "$DOWNLOAD_URL" | grep -qE '^https://storage\.googleapis\.com/antigravity-public/'; then
        echo "Error: Could not resolve valid release URL from $DOWNLOAD_PAGE." >&2
        echo "Usage: update-antigravity [path/to/antigravity-linux-x64.tar.gz]" >&2
        exit 1
    fi

    # Check if we already have this exact build AND the binary exists
    STAMP_FILE="$HOME/.local/share/dotfiles/antigravity.url"
    if [ -f "$STAMP_FILE" ] && [ -x "$INSTALL_DIR/antigravity" ] && [ "$(cat "$STAMP_FILE")" = "$DOWNLOAD_URL" ]; then
        echo "Antigravity hub is already up to date."
        exit 0
    fi

    echo "Found latest release URL: $DOWNLOAD_URL"
    TARBALL_PATH=$(mktemp /tmp/antigravity-XXXXXX.tar.gz)
    IS_TEMP_FILE=true
    trap 'if [ "$IS_TEMP_FILE" = true ] && [ -f "$TARBALL_PATH" ]; then rm -f "$TARBALL_PATH"; fi' EXIT

    echo "Downloading to $TARBALL_PATH..."
    curl -L --progress-bar --max-redirs 5 "$DOWNLOAD_URL" -o "$TARBALL_PATH"
fi


if [ ! -f "$TARBALL_PATH" ]; then
    echo "Error: Archive file '$TARBALL_PATH' does not exist." >&2
    exit 1
fi

if ! file "$TARBALL_PATH" | grep -q 'gzip compressed data'; then
    echo "Error: Archive '$TARBALL_PATH' is not a valid gzip compressed archive." >&2
    exit 1
fi

if tar -tzf "$TARBALL_PATH" | grep -qE '(^|/)\.\.(/|$)|^/'; then
    echo "Error: Suspicious path traversal entries detected in archive." >&2
    exit 1
fi

echo "Updating Antigravity in $INSTALL_DIR..."
mkdir -p "$(dirname "$INSTALL_DIR")"
TMP_EXTRACT="$(mktemp -d "${INSTALL_DIR}.tmp.XXXXXX")"
tar -xzf "$TARBALL_PATH" -C "$TMP_EXTRACT" --strip-components=1 --no-same-owner

# Atomic swap into INSTALL_DIR
BACKUP_DIR="${INSTALL_DIR}.old"
rm -rf "$BACKUP_DIR"
if [ -d "$INSTALL_DIR" ]; then
    mv "$INSTALL_DIR" "$BACKUP_DIR"
fi

if mv "$TMP_EXTRACT" "$INSTALL_DIR"; then
    rm -rf "$BACKUP_DIR"
else
    echo "Error: Failed to move new Antigravity version into place. Restoring backup..." >&2
    if [ -d "$BACKUP_DIR" ]; then
        mv "$BACKUP_DIR" "$INSTALL_DIR"
    fi
    rm -rf "$TMP_EXTRACT"
    exit 1
fi

# Fix SELinux file contexts after extraction (required on Fedora Kinoite)
if command -v restorecon &>/dev/null; then
    restorecon -R "$INSTALL_DIR" 2>/dev/null || true
fi

NEW_VER=$(jq -r '.version' "$INSTALL_DIR/resources/app/package.json" 2>/dev/null || echo "Unknown")
if [ -n "${DOWNLOAD_URL:-}" ] && [ -n "${STAMP_FILE:-}" ]; then
    mkdir -p "$(dirname "$STAMP_FILE")"
    echo "$DOWNLOAD_URL" > "$STAMP_FILE"
fi
echo "Update complete! Installed version: $NEW_VER"

