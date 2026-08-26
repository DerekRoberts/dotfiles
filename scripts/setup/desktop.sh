#!/usr/bin/env bash
# desktop.sh — KDE Plasma desktop layout, panel, system tray, notifications & input
#
# Usage:
#   scripts/setup/desktop.sh [--dev|--desktop]
#   scripts/setup/desktop.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# ── Natural Scrolling ────────────────────────────────────────────────────────

configure_natural_scroll() {
    section "Natural Scrolling Configuration"

    if ! command -v kwriteconfig6 &>/dev/null; then
        warn "kwriteconfig6 not found — skipping natural scroll configuration"
        return
    fi

    info "Enabling natural scrolling for pointers and touchpads..."
    # The [Mouse] and [Touchpad] groups are the fallback KWin applies to any
    # device without its own [Libinput][...] override, which is what we want:
    # every device, including ones plugged in later.
    local group
    for group in Mouse Touchpad; do
        kwriteconfig6 --file kcminputrc --group "$group" --key NaturalScroll true
        kwriteconfig6 --file kcminputrc --group "$group" --key XLbInptNaturalScroll true
    done

    kwin_reconfigure
    success "Natural scrolling enabled"
}

# ── Plasma Desktop, Panel & Kickoff Menu ─────────────────────────────────────

configure_kickoff_favorites() {
    local PROFILE="${1:-dev}"
    local PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    local WAS_KACTIVITY_ACTIVE=false

    # kactivitymanagerd caches statsrc in memory and would overwrite our edit.
    if command -v systemctl &>/dev/null && systemctl --user is-active plasma-kactivitymanagerd &>/dev/null; then
        if systemctl --user stop plasma-kactivitymanagerd >/dev/null 2>&1; then
            WAS_KACTIVITY_ACTIVE=true
        fi
    fi

    python3 - "$PLASMA_CONFIG" "$PROFILE" << 'PY'
import sys, os, re, configparser

appletsrc, profile = sys.argv[1], sys.argv[2]

if profile == "desktop":
    ordering = "google-chrome.desktop,org.kde.dolphin.desktop,org.kde.discover.desktop,systemsettings.desktop"
else:
    ordering = "antigravity.desktop,cursor.desktop,org.kde.discover.desktop,org.kde.dolphin.desktop,google-chrome.desktop,systemsettings.desktop"

# Read-only discovery of kickoff applet ids and activity uuids.
applet_ids, activity_ids = [], []
if os.path.exists(appletsrc):
    with open(appletsrc, "r") as f:
        content = f.read()

    def body_after(match):
        end = content.find("\n[", match.end())
        return content[match.end():end if end != -1 else len(content)]

    for m in re.finditer(r"^\[Containments\]\[\d+\]\[Applets\]\[(\d+)\]\s*$", content, re.M):
        if "plugin=org.kde.plasma.kickoff" in body_after(m):
            applet_ids.append(m.group(1))

    for m in re.finditer(r"^\[Containments\]\[\d+\]\s*$", content, re.M):
        act = re.search(r"^activityId=([a-f0-9-]+)", body_after(m), re.M)
        if act and act.group(1) not in activity_ids:
            activity_ids.append(act.group(1))

# Default applet id on a stock Plasma panel.
applet_ids = applet_ids or ["3"]

statsrc = os.path.expanduser("~/.config/kactivitymanagerd-statsrc")
config = configparser.RawConfigParser()
config.optionxform = str
if os.path.exists(statsrc):
    config.read(statsrc)

for applet_id in applet_ids:
    for scope in ["global"] + activity_ids:
        section = f"Favorites-org.kde.plasma.kickoff.favorites.instance-{applet_id}-{scope}"
        if not config.has_section(section):
            config.add_section(section)
        config.set(section, "ordering", ordering)

os.makedirs(os.path.dirname(statsrc), exist_ok=True)
tmp = statsrc + ".tmp"
with open(tmp, "w") as f:
    config.write(f, space_around_delimiters=False)
os.replace(tmp, statsrc)
PY

    if [[ "$WAS_KACTIVITY_ACTIVE" == true ]]; then
        systemctl --user start plasma-kactivitymanagerd >/dev/null 2>&1 || true
    fi
}

configure_plasma_desktop() {
    local PROFILE="${1:-dev}"
    section "KDE Plasma Desktop & Panel Layout"

    info "Configuring KDE Plasma desktops (DarkestHour wallpaper), panel & menu favorites..."

    # Kickoff favourites live in kactivitymanagerd-statsrc, keyed by the applet
    # id and activity uuid, which we read out of appletsrc. appletsrc itself is
    # owned by plasmashell — read it, never rewrite it. The desktop and panel
    # below are set through the supported scripting API instead.
    rebuild_ksycoca
    configure_kickoff_favorites "$PROFILE"

    local PANEL_SCRIPT='
var d = desktops();
for (var i = 0; i < d.length; i++) {
    d[i].writeConfig("plugin", "org.kde.desktopcontainment");
    d[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d[i].writeConfig("Image", "/usr/share/wallpapers/DarkestHour");
    d[i].reloadConfig();
}
var p = panels();
for (var i = 0; i < p.length; i++) {
    p[i].location = "left";
    p[i].hiding = "dodgewindows";
    p[i].height = 72;
    var ws = p[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === "org.kde.plasma.showdesktop" || ws[j].type === "org.kde.plasma.peekatdesktop") {
            ws[j].remove();
        } else if (ws[j].type === "org.kde.plasma.icontasks") {
            ws[j].currentConfigGroup = ["General"];
            ws[j].writeConfig("launchers", "applications:org.kde.dolphin.desktop,applications:com.google.Chrome.desktop");
            ws[j].reloadConfig();
        }
    }
}
'
    local QDBUS
    if QDBUS="$(qdbus_bin)"; then
        "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    fi

    rebuild_ksycoca
    success "Desktops (DarkestHour), panel layout & task manager configured"
}

# ── Notifications ────────────────────────────────────────────────────────────

configure_notifications() {
    section "KDE Notification Preferences"

    if ! command -v kwriteconfig6 &>/dev/null; then
        warn "kwriteconfig6 not found — skipping notification configuration"
        return
    fi

    info "Configuring KDE notification rules (silencing Antigravity and Cursor)..."
    local NOTIFY_CONFIG="$HOME/.config/plasmanotifyrc"
    local NOTIFY_DIR; NOTIFY_DIR="$(dirname "$NOTIFY_CONFIG")"
    mkdir -p "$NOTIFY_DIR"
    # Edit a copy and swap it in, so a crash mid-write can't truncate the live file.
    local TMP_NOTIFY; TMP_NOTIFY="$(mktemp -p "$NOTIFY_DIR" .plasmanotifyrc.tmp.XXXXXX)"
    [[ -f "$NOTIFY_CONFIG" ]] && cp -f "$NOTIFY_CONFIG" "$TMP_NOTIFY"
    local app key
    for app in antigravity cursor; do
        kwriteconfig6 --file "$TMP_NOTIFY" --group Applications --group "$app" --key Seen true
        for key in ShowPopups ShowInHistory ShowBadges; do
            kwriteconfig6 --file "$TMP_NOTIFY" --group Applications --group "$app" --key "$key" false
        done
    done
    chmod 600 "$TMP_NOTIFY"
    mv -f "$TMP_NOTIFY" "$NOTIFY_CONFIG"
    success "KDE notifications silenced for Antigravity and Cursor"
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
Usage:
  scripts/setup/desktop.sh [OPTIONS]

Options:
  --dev       Apply dev profile KDE layout and Kickoff menu favorites (default)
  --desktop   Apply desktop profile KDE layout and Kickoff menu favorites
  --help, -h  Show this help
EOF
}

main() {
    local PROFILE="dev"
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

    echo "=== Configuring KDE Plasma Desktop & Input ($PROFILE profile) ==="
    configure_natural_scroll
    configure_plasma_desktop "$PROFILE"
    configure_notifications
    success "Desktop environment configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
