#!/usr/bin/env bash
# clone-repos.sh — Declarative repo cloner
# Reads config/repos.txt (SSH paths: org/repo), clones into ~/Repos/
# Generates an SSH key if ~/.ssh/id_ed25519 is absent.
#
# Usage: scripts/clone-repos.sh [--repos-file PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_FILE="$REPO_DIR/config/repos.txt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repos-file)
            [[ -n "${2:-}" ]] || { echo "❌ Missing path after --repos-file" >&2; exit 1; }
            REPOS_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: clone-repos.sh [--repos-file PATH]"
            exit 0
            ;;
        *)
            if [[ -f "$1" ]]; then
                REPOS_FILE="$1"
                shift
            else
                echo "❌ Unknown option or missing file: $1" >&2
                exit 1
            fi
            ;;
    esac
done

CLONE_DIR="${HOME}/Repos"
SSH_KEY="${HOME}/.ssh/id_ed25519"

# ── Helpers ─────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib.sh
. "$REPO_DIR/scripts/lib.sh"

die() { echo "❌ $*" >&2; exit 1; }

# ── SSH Key ──────────────────────────────────────────────────────────────────

ensure_ssh_key() {
    if [[ -f "$SSH_KEY" ]]; then
        info "SSH key already exists: $SSH_KEY"
        return
    fi

    echo ""
    echo "=== SSH Key Setup ==="
    echo "No SSH key found at $SSH_KEY. Generating a new ed25519 key..."

    local comment
    comment="$(git config --global user.email 2>/dev/null || hostname)"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    ssh-keygen -t ed25519 -C "$comment" -f "$SSH_KEY" -N "" -q

    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "  Your new public SSH key — add it to GitHub:"
    echo "  https://github.com/settings/keys"
    echo ""
    echo "  IMPORTANT: To verify commits, you must add it TWICE:"
    echo "    1) Type: Authentication Key (to clone repos)"
    echo "    2) Type: Signing Key (to get Verified commit badges)"
    echo ""
    cat "${SSH_KEY}.pub"
    echo "══════════════════════════════════════════════════════════"
    echo ""

    # Open browser non-blocking (best-effort on Kinoite/KDE)
    if command -v xdg-open &>/dev/null; then
        xdg-open "https://github.com/settings/keys" &>/dev/null &
    fi

    echo "Press Enter once you have added the key to GitHub..."
    # Read from /dev/tty to work when piped
    if [[ -t 0 ]]; then
        read -r
    elif [[ -c /dev/tty ]] && { true </dev/tty; } 2>/dev/null; then
        read -r </dev/tty
    fi
    echo ""
}

# ── Repo Cloning ─────────────────────────────────────────────────────────────

clone_repos() {
    [[ -f "$REPOS_FILE" ]] || die "Repos file not found: $REPOS_FILE"

    mkdir -p "$CLONE_DIR"

    local cloned=0 skipped=0 failed=0

    echo ""
    echo "=== Cloning Repos → $CLONE_DIR ==="

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip whitespace and skip comments / blank lines
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        local org repo target
        org="${line%%/*}"
        repo="${line#*/}"
        target="$CLONE_DIR/$repo"

        if [[ -d "$target/.git" ]]; then
            info "$repo — already cloned, skipping"
            link_cursor_dotfiles_mdc "$target" || true
            ((skipped++)) || true
            continue
        fi

        local url="git@github.com:${org}/${repo}.git"
        info "Cloning $url → $target"

        if git clone --filter=blob:none "$url" "$target" 2>&1 | sed 's/^/    /'; then
            success "$repo cloned"
            link_cursor_dotfiles_mdc "$target" || true
            ((cloned++)) || true
        else
            warn "$repo — clone failed (SSH key loaded? Repo access granted?)"
            ((failed++)) || true
        fi
    done < "$REPOS_FILE"

    echo ""
    echo "=== Clone Summary ==="
    echo "  Cloned:  $cloned"
    echo "  Skipped: $skipped (already present)"
    if [[ "$failed" -gt 0 ]]; then
        warn "$failed repo(s) failed to clone (SSH key not yet authorized on GitHub)."
        info "Once your key is added to https://github.com/settings/keys, re-run:"
        info "  scripts/clone-repos.sh"
        echo ""
        return 1
    fi
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    ensure_ssh_key
    if clone_repos; then
        echo "✅ Repository setup complete."
    else
        echo "⚠ Repository setup completed with warnings."
        exit 1
    fi
}


main "$@"
