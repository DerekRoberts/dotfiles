#!/usr/bin/env bash
# lib.sh — helpers shared by the setup scripts. Source it; don't run it.
#
#   # shellcheck source=scripts/lib.sh
#   . "$DOTFILES_DIR/scripts/lib.sh"

# ── Output ───────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# ── File installation ────────────────────────────────────────────────────────

# Copy src to dest. If dest is a symlink, replace the link — never write through
# it, dest may point at the git work tree.
install_copy() {
    local src="$1" dest="$2" mode="${3:-755}"
    mkdir -p "$(dirname "$dest")"
    if [[ -L "$dest" ]]; then
        rm -f "$dest"
    fi
    install -m "$mode" "$src" "$dest"
}

# ── Download guards ──────────────────────────────────────────────────────────
#
# Nothing here is a substitute for signature verification; these guards only
# ensure that a URL or archive we got from the network can't redirect a fetch or
# an extraction somewhere we didn't intend.

# A URL parsed out of a network response must sit under an expected prefix
# before we fetch it and mark it executable.
require_url_prefix() {
    local url="$1" prefix="$2"
    [[ -n "$url" && "$url" == "$prefix"* ]]
}

# Verify a file against an expected sha256. Worth doing wherever upstream
# publishes one; most vendors used here don't, so callers pass it when they can.
verify_sha256() {
    local file="$1" expected="$2" actual
    [[ -n "$expected" ]] || return 1
    actual="$(sha256sum "$file" | cut -d' ' -f1)" || return 1
    [[ "$actual" == "$expected" ]]
}

# Reject archives whose members are absolute, traverse upwards, or are links
# aimed outside the extraction directory.

# ── Upstream endpoints ───────────────────────────────────────────────────────

CURSOR_DOWNLOAD_API='https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=latest'
CURSOR_URL_PREFIX='https://downloads.cursor.com/'

# Resolve the current Cursor AppImage URL. The API response decides what we
# fetch and mark executable, so refuse anything that isn't on Cursor's CDN.
cursor_latest_url() {
    local url
    url="$(curl -fsSL --connect-timeout 10 --max-time 20 "$CURSOR_DOWNLOAD_API" \
        | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4 || true)"
    require_url_prefix "$url" "$CURSOR_URL_PREFIX" || return 1
    printf '%s\n' "$url"
}

# Load nvm, select default/LTS Node, and require npm from nvm's prefix under $HOME.
load_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    [[ -s "$NVM_DIR/nvm.sh" ]] || return 1
    # shellcheck source=/dev/null
    \. "$NVM_DIR/nvm.sh"
    nvm use default >/dev/null 2>&1 || nvm use --lts >/dev/null 2>&1 || return 1
    local npm_bin prefix
    npm_bin="$(type -p npm 2>/dev/null)" || return 1
    [[ "$npm_bin" == "$NVM_DIR"/* ]] || return 1
    prefix="$(npm prefix -g)" || return 1
    [[ "$prefix" == "$HOME"/* ]] || return 1
}

kilo_cli_installed() {
    npm list -g --depth=0 @kilocode/cli >/dev/null 2>&1
}

# npm 11+ needs an explicit allowlist for global lifecycle scripts; older npm runs them by default.
install_kilo_cli_pkg() {
    local major
    major="$(npm -v | cut -d. -f1)"
    [[ "$major" =~ ^[0-9]+$ ]] || return 1
    if [[ "$major" -ge 11 ]]; then
        npm install -g --allow-scripts=@kilocode/cli @kilocode/cli
    else
        npm install -g @kilocode/cli
    fi
}

# ── Insync ───────────────────────────────────────────────────────────────────

# Live on this boot? One check: a real executable on PATH. Layering is setup's
# only privileged step; after that, `rpm-ostree upgrade` (updown) owns versions.
insync_is_live() {
    type -p insync >/dev/null 2>&1
}

# Layered packages are not on PATH until reboot. Ask when stdin is a TTY;
# otherwise print the reminder (curl|bash / CI must not block on `read`).
prompt_reboot_for_insync() {
    echo ""
    echo "Insync was layered and will be available after reboot."
    if [[ ! -t 0 ]]; then
        echo "Reboot when ready."
        return 0
    fi
    local ans=""
    read -r -p "Reboot now? [y/N] " ans || true
    case "$ans" in
        y|Y|yes|YES)
            sudo systemctl reboot
            ;;
    esac
}

# ── Icon themes ──────────────────────────────────────────────────────────────

# The Insync installer used to copy its icons into directories that shadow the
# system icon themes: ~/.local/share/icons/{breeze,breeze-dark} holding only
# status icons and no index.theme, plus hicolor's size directories dumped into
# ~/.icons, where each name is read as a theme. A theme directory that ranks
# ahead of /usr/share/icons but has no index.theme makes every lookup against
# that theme fail — which is what leaves the Dolphin launcher icon blank.
# Insync's icons belong in hicolor alone; every theme already falls back to it.
# Move offenders aside rather than deleting, in case something else landed there.

# ── KDE ──────────────────────────────────────────────────────────────────────

# Invalidate and rebuild KDE system configuration cache.
rebuild_ksycoca() {
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi
}

# Restart plasmashell if active under systemd. Best effort: absent on a headless run.
plasmashell_restart() {
    if command -v systemctl &>/dev/null && systemctl --user is-active plasma-plasmashell &>/dev/null; then
        systemctl --user restart plasma-plasmashell >/dev/null 2>&1 || true
    fi
}

# Plasma 6 ships qdbus under several names depending on the image.
qdbus_bin() {
    local b
    for b in qdbus-qt6 qdbus6 qdbus; do
        if command -v "$b" &>/dev/null; then
            printf '%s\n' "$b"
            return 0
        fi
    done
    return 1
}

# Ask KWin to re-read its configuration. Best effort: absent on a headless run.
kwin_reconfigure() {
    local q
    q="$(qdbus_bin)" || return 0
    "$q" org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
}

