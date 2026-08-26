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

# ── Insync ───────────────────────────────────────────────────────────────────

INSYNC_YUM_PREFIX='http://yum.insync.io/fedora/'

# True if $1 is a lower EVR than $2 (strings like 3.9.11.60043-fc44).
# ponytail: sort -V, not rpm.labelCompare — Insync EVRs are dotted-numeric with a
# matching dist tag; switch to rpmdev-vercmp if epoch or rpm-odd suffixes appear.
evr_older_than() {
    local a="$1" b="$2"
    [[ -n "$a" && -n "$b" && "$a" != "$b" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" == "$b" ]]
}

# Latest insync VERSION-RELEASE from the yum repo. No root needed.
insync_repo_evr() {
    local rel href primary listing evr
    rel="$(rpm -E '%fedora' 2>/dev/null)" || return 1
    [[ "$rel" =~ ^[0-9]+$ ]] || return 1
    href="$(curl -fsSL --connect-timeout 10 --max-time 20 \
        "${INSYNC_YUM_PREFIX}${rel}/repodata/repomd.xml" \
        | grep -o 'href="repodata/[^"]*-primary.xml.gz"' \
        | head -1 | cut -d'"' -f2)" || return 1
    primary="${INSYNC_YUM_PREFIX}${rel}/${href}"
    require_url_prefix "$primary" "${INSYNC_YUM_PREFIX}${rel}/repodata/" || return 1
    listing="$(curl -fsSL --connect-timeout 10 --max-time 20 "$primary" | gzip -dc)" || return 1
    evr="$(printf '%s\n' "$listing" \
        | grep -o 'href="x86_64/insync-[0-9][^"]*\.x86_64\.rpm"' \
        | sed -e 's|^href="x86_64/insync-||' -e 's|\.x86_64\.rpm"$||' \
        | sort -V | tail -1)"
    [[ -n "$evr" ]] || return 1
    printf '%s\n' "$evr"
}

insync_update_available() {
    local installed latest
    installed="$(rpm -q --qf '%{VERSION}-%{RELEASE}' insync 2>/dev/null)" || return 1
    latest="$(insync_repo_evr)" || return 1
    evr_older_than "$installed" "$latest"
}

# True when setup still has privileged Insync work: missing, or a newer RPM in the repo.
insync_needs_root() {
    if ! rpm -q insync &>/dev/null; then
        return 0
    fi
    insync_update_available
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

