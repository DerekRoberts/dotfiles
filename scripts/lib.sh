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
tar_is_safe() {
    local archive="$1" listing
    listing="$(tar -tzf "$archive" 2>/dev/null)" || return 1
    [[ -n "$listing" ]] || return 1
    if grep -qE '(^|/)\.\.(/|$)|^/' <<< "$listing"; then
        return 1
    fi
    # Link entries are applied before later members are written, so a link
    # pointing outside the directory turns a normal member into an escape.
    if tar -tvzf "$archive" 2>/dev/null | grep -E '^[hl]' \
        | grep -qE '(-> |link to )(/|.*\.\.(/|$))'; then
        return 1
    fi
    return 0
}

# ── Upstream endpoints ───────────────────────────────────────────────────────

CURSOR_DOWNLOAD_API='https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable'
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

# Insync ships no Flatpak or AppImage, so it runs from ~/.local/lib via this
# wrapper. Written from one place because both the installer and the updater
# need it to stay identical.
write_insync_wrapper() {
    local dest="$1"
    mkdir -p "$(dirname "$dest")"
    cat > "$dest" << 'EOF'
#!/bin/bash
export LC_TIME=C
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export XDG_DATA_DIRS="$HOME/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Insync reads its tray icons from /usr/share/icons, which we can't write on an
# ostree host. bwrap is used only to graft our icon dir over that path; it is
# not a sandbox (/ is bind-mounted through unchanged).
if command -v bwrap &>/dev/null && [[ -d "$HOME/.local/share/icons/hicolor" ]]; then
    exec bwrap --dev-bind / / --bind "$HOME/.local/share/icons/hicolor" /usr/share/icons/hicolor "$HOME/.local/lib/insync/insync" "$@" || exec "$HOME/.local/lib/insync/insync" "$@"
else
    exec "$HOME/.local/lib/insync/insync" "$@"
fi
EOF
    chmod +x "$dest"
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
repair_icon_theme_pollution() {
    local stash="$HOME/.local/share/dotfiles/icon-pollution"
    local stamp dir moved=0
    stamp="$(date +%s)"

    for dir in "$HOME/.local/share/icons/breeze" "$HOME/.local/share/icons/breeze-dark"; do
        [[ -d "$dir" && ! -f "$dir/index.theme" ]] || continue
        mkdir -p "$stash"
        mv "$dir" "$stash/$(basename "$dir").$stamp"
        moved=1
    done

    # A size or "scalable" directory is never a valid theme name.
    for dir in "$HOME"/.icons/*; do
        [[ -d "$dir" && ! -f "$dir/index.theme" ]] || continue
        case "$(basename "$dir")" in
            [0-9]*x[0-9]*|scalable)
                mkdir -p "$stash"
                mv "$dir" "$stash/dot-icons-$(basename "$dir").$stamp"
                moved=1
                ;;
        esac
    done

    if [[ "$moved" -eq 1 ]]; then
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -f -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
        fi
        info "Moved shadowing icon theme directories to $stash"
    fi
}

# ── KDE ──────────────────────────────────────────────────────────────────────

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

self_test_lib() {
    local tmp
    tmp="$(mktemp -d)"

    echo payload > "$tmp/src"
    echo original > "$tmp/repo"
    ln -s "$tmp/repo" "$tmp/dest"
    install_copy "$tmp/src" "$tmp/dest" 644
    if [[ -L "$tmp/dest" ]]; then
        echo "FAIL: dest is still a symlink" >&2; rm -rf "$tmp"; return 1
    fi
    if [[ "$(cat "$tmp/dest")" != "payload" ]]; then
        echo "FAIL: dest content" >&2; rm -rf "$tmp"; return 1
    fi
    if [[ "$(cat "$tmp/repo")" != "original" ]]; then
        echo "FAIL: wrote through symlink into target" >&2; rm -rf "$tmp"; return 1
    fi

    require_url_prefix "https://example.com/a/b" "https://example.com/a/" \
        || { echo "FAIL: rejected a matching prefix" >&2; rm -rf "$tmp"; return 1; }
    if require_url_prefix "https://evil.test/x" "https://example.com/"; then
        echo "FAIL: accepted a foreign host" >&2; rm -rf "$tmp"; return 1
    fi
    if require_url_prefix "" "https://example.com/"; then
        echo "FAIL: accepted an empty URL" >&2; rm -rf "$tmp"; return 1
    fi

    echo checkme > "$tmp/hashed"
    local sum
    sum="$(sha256sum "$tmp/hashed" | cut -d' ' -f1)"
    verify_sha256 "$tmp/hashed" "$sum" \
        || { echo "FAIL: rejected a matching sha256" >&2; rm -rf "$tmp"; return 1; }
    if verify_sha256 "$tmp/hashed" "${sum/#?/0}"; then
        echo "FAIL: accepted a mismatched sha256" >&2; rm -rf "$tmp"; return 1
    fi
    if verify_sha256 "$tmp/hashed" ""; then
        echo "FAIL: accepted an empty sha256" >&2; rm -rf "$tmp"; return 1
    fi

    mkdir -p "$tmp/good"
    echo bin > "$tmp/good/tool"
    tar -czf "$tmp/good.tar.gz" -C "$tmp" good
    tar_is_safe "$tmp/good.tar.gz" \
        || { echo "FAIL: rejected a clean archive" >&2; rm -rf "$tmp"; return 1; }

    # GNU tar strips "../" on extraction, but an archive containing it is still
    # a signal we want to refuse rather than silently rewrite.
    tar -czf "$tmp/trav.tar.gz" -C "$tmp" --transform 's|^good|../good|' good 2>/dev/null
    if tar_is_safe "$tmp/trav.tar.gz"; then
        echo "FAIL: accepted a traversing archive" >&2; rm -rf "$tmp"; return 1
    fi

    mkdir -p "$tmp/link"
    ln -s /etc "$tmp/link/escape"
    tar -czf "$tmp/link.tar.gz" -C "$tmp" link
    if tar_is_safe "$tmp/link.tar.gz"; then
        echo "FAIL: accepted an archive linking outside the tree" >&2; rm -rf "$tmp"; return 1
    fi

    if tar_is_safe "$tmp/does-not-exist.tar.gz"; then
        echo "FAIL: accepted a missing archive" >&2; rm -rf "$tmp"; return 1
    fi

    # repair_icon_theme_pollution reads $HOME; point it at the sandbox.
    local HOME="$tmp/home"
    mkdir -p "$HOME/.local/share/icons/breeze/status/22" "$HOME/.icons/48x48/status"
    mkdir -p "$HOME/.local/share/icons/breeze-dark"
    printf '[Icon Theme]\nName=Real\n' > "$HOME/.local/share/icons/breeze-dark/index.theme"
    mkdir -p "$HOME/.icons/MyTheme"
    printf '[Icon Theme]\nName=Mine\n' > "$HOME/.icons/MyTheme/index.theme"
    repair_icon_theme_pollution >/dev/null

    if [[ -d "$HOME/.local/share/icons/breeze" ]]; then
        echo "FAIL: left a themeless breeze dir shadowing the system theme" >&2; rm -rf "$tmp"; return 1
    fi
    if [[ -d "$HOME/.icons/48x48" ]]; then
        echo "FAIL: left a size-named dir in ~/.icons" >&2; rm -rf "$tmp"; return 1
    fi
    if [[ ! -f "$HOME/.local/share/icons/breeze-dark/index.theme" ]]; then
        echo "FAIL: removed a valid theme that has an index.theme" >&2; rm -rf "$tmp"; return 1
    fi
    if [[ ! -f "$HOME/.icons/MyTheme/index.theme" ]]; then
        echo "FAIL: removed a real user theme" >&2; rm -rf "$tmp"; return 1
    fi

    rm -rf "$tmp"
    echo "lib self-test passed"
}
