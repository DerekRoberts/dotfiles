#!/usr/bin/env bash
# desktop.sh — KDE Plasma desktop layout, panel, system tray, notifications & input
#
# Usage:
#   scripts/setup/desktop.sh [--dev|--desktop]
#   scripts/setup/desktop.sh --help

set -euo pipefail


# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
section() { echo ""; echo "=== $* ==="; }

# ── Natural Scrolling ────────────────────────────────────────────────────────

configure_natural_scroll() {
    section "Natural Scrolling Configuration"

    if command -v kwriteconfig6 &>/dev/null || [[ -f "$HOME/.config/kcminputrc" ]]; then
        info "Configuring natural scrolling globally for all devices in KDE..."

        # 1. Global fallback groups
        if command -v kwriteconfig6 &>/dev/null; then
            kwriteconfig6 --file kcminputrc --group Mouse --key NaturalScroll true
            kwriteconfig6 --file kcminputrc --group Mouse --key XLbInptNaturalScroll true
            kwriteconfig6 --file kcminputrc --group Touchpad --key NaturalScroll true
            kwriteconfig6 --file kcminputrc --group Touchpad --key XLbInptNaturalScroll true
        fi

        # 2. Discover all connected hardware pointers and ensure every section in kcminputrc has NaturalScroll=true
        python3 - "$HOME/.config/kcminputrc" << 'PY'
import sys, re, os, subprocess

path = sys.argv[1]
discovered_devices = []

# Query live KWin InputDeviceManager on D-Bus if available
try:
    cmd = ["qdbus-qt6", "org.kde.KWin", "/org/kde/KWin/InputDevice", "org.kde.KWin.InputDeviceManager.ListPointers"]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
    if res.returncode == 0:
        for dev in res.stdout.strip().splitlines():
            dev = dev.strip()
            if not dev:
                continue
            dev_path = f"/org/kde/KWin/InputDevice/{dev}"
            def get_prop(prop):
                r = subprocess.run(["qdbus-qt6", "org.kde.KWin", dev_path, "org.freedesktop.DBus.Properties.Get", "org.kde.KWin.InputDevice", prop], capture_output=True, text=True, timeout=1)
                return r.stdout.strip()
            
            supports = get_prop("supportsNaturalScroll")
            if supports.lower() == "true":
                vendor = get_prop("vendor")
                product = get_prop("product")
                name = get_prop("name")
                if vendor and product and name:
                    discovered_devices.append((vendor, product, name))
                    # Apply live to active session
                    subprocess.run(["qdbus-qt6", "org.kde.KWin", dev_path, "org.freedesktop.DBus.Properties.Set", "org.kde.KWin.InputDevice", "naturalScroll", "true"], capture_output=True, timeout=1)
except Exception:
    pass

# Supplementary hardware discovery via /proc/bus/input/devices
proc_path = "/proc/bus/input/devices"
if os.path.exists(proc_path):
    try:
        with open(proc_path, "r") as f:
            content = f.read()
        for b in content.strip().split("\n\n"):
            handlers = re.search(r"H: Handlers=.*(mouse|event).*", b)
            if not handlers:
                continue
            name_match = re.search(r'N: Name="([^"]+)"', b)
            id_match = re.search(r"I: Bus=(\w+) Vendor=(\w+) Product=(\w+)", b)
            if name_match and id_match:
                name = name_match.group(1)
                vendor_hex = id_match.group(2)
                product_hex = id_match.group(3)
                vendor_dec = str(int(vendor_hex, 16))
                product_dec = str(int(product_hex, 16))
                if any(k in name.lower() for k in ("mouse", "touchpad", "trackpoint", "trackball", "pointer")):
                    discovered_devices.append((vendor_dec, product_dec, name))
    except Exception:
        pass

lines = []
if os.path.exists(path):
    with open(path, "r") as f:
        lines = f.readlines()

new_lines = []
in_target = False
found_natural = False
target_keys = ("NaturalScroll", "XLbInptNaturalScroll")
seen_sections = set()

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_target and not found_natural:
            new_lines.append("NaturalScroll=true\n")
        in_target = "Libinput" in stripped or stripped in ("[Mouse]", "[Touchpad]")
        found_natural = False
        seen_sections.add(stripped)
        new_lines.append(line)
        continue

    if in_target and any(stripped.startswith(k + "=") for k in target_keys):
        new_lines.append(re.sub(r"=\s*(false|0)", "=true", line))
        found_natural = True
        continue

    new_lines.append(line)

if in_target and not found_natural:
    new_lines.append("NaturalScroll=true\n")

# Append newly discovered device sections if missing
for v, p, n in set(discovered_devices):
    section_hdr = f"[Libinput][{v}][{p}][{n}]"
    if section_hdr not in seen_sections:
        new_lines.append(f"\n{section_hdr}\nNaturalScroll=true\n")
        seen_sections.add(section_hdr)

os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
with open(path, "w") as f:
    f.writelines(new_lines)
PY

        # Notify KWin / KDE input daemon of configuration changes
        if command -v qdbus-qt6 &>/dev/null; then
            qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        elif command -v qdbus6 &>/dev/null; then
            qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        elif command -v qdbus &>/dev/null; then
            qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        fi
        success "Natural scrolling enabled for all connected and configured devices"
    fi
}

# ── Plasma Desktop, Panel & Kickoff Menu ─────────────────────────────────────

configure_plasma_desktop() {
    local PROFILE="${1:-dev}"
    section "KDE Plasma Desktop & Panel Layout"

    info "Configuring KDE Plasma desktops (DarkestHour wallpaper), panel, system tray & menu favorites..."
    local PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    local WAS_PLASMASHELL_ACTIVE=false
    local WAS_KACTIVITY_ACTIVE=false

    if command -v systemctl &>/dev/null; then
        if systemctl --user is-active plasma-plasmashell &>/dev/null; then
            if systemctl --user stop plasma-plasmashell >/dev/null 2>&1; then
                WAS_PLASMASHELL_ACTIVE=true
            fi
        fi
        if systemctl --user is-active plasma-kactivitymanagerd &>/dev/null; then
            if systemctl --user stop plasma-kactivitymanagerd >/dev/null 2>&1; then
                WAS_KACTIVITY_ACTIVE=true
            fi
        fi
    fi

    if [[ -f "$PLASMA_CONFIG" ]]; then
        python3 - "$PLASMA_CONFIG" "$PROFILE" << 'PY'
import sys, os, re, configparser

path = sys.argv[1]
profile = sys.argv[2] if len(sys.argv) > 2 else "dev"
if not os.path.exists(path):
    sys.exit(0)

with open(path, "r") as f:
    content = f.read()

# 1. Ensure all desktop containments use org.kde.desktopcontainment
lines = content.splitlines(True)
new_lines = []
in_desktop = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[Containments][") and stripped.endswith("]"):
        parts = stripped[1:-1].split("][")
        in_desktop = len(parts) == 2
    elif stripped.startswith("["):
        in_desktop = False
    elif in_desktop and stripped == "plugin=org.kde.plasma.folder":
        line = "plugin=org.kde.desktopcontainment\n"
    new_lines.append(line)

content = "".join(new_lines)

# 2. System Tray sub-applets & visibility preferences
core_plugins = [
    "org.kde.plasma.volume",
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.brightness",
    "org.kde.plasma.notifications",
    "org.kde.plasma.clipboard",
    "org.kde.plasma.devicenotifier",
    "org.kde.plasma.cameraindicator",
    "org.kde.kdeconnect",
    "org.kde.plasma.vault",
    "org.kde.kscreen"
]

tray_hdr = None
for m in re.finditer(r"^(\[Containments\]\[\d+\]\[Applets\]\[\d+\])\s*$", content, re.M):
    hdr = m.group(1)
    body_end = content.find("\n[", m.end())
    body = content[m.end():body_end if body_end != -1 else len(content)]
    if "plugin=org.kde.plasma.systemtray" in body:
        tray_hdr = hdr
        break

if tray_hdr:
    # Collect existing child applet IDs and plugins
    existing_ids = [int(m) for m in re.findall(re.escape(tray_hdr) + r"\[Applets\]\[(\d+)\]", content)]
    next_id = max(existing_ids) + 1 if existing_ids else 30
    
    existing_plugins = []
    for m in re.finditer(re.escape(tray_hdr) + r"\[Applets\]\[\d+\][\s\S]*?plugin=([\w\.\-]+)", content):
        existing_plugins.append(m.group(1))
    
    # Add missing core child applets
    additions = []
    for plugin in core_plugins:
        if plugin not in existing_plugins:
            additions.append(f"\n{tray_hdr}[Applets][{next_id}]\nimmutability=1\nplugin={plugin}\n")
            next_id += 1
    
    if additions:
        content += "".join(additions)

    # Ensure [General] section exists with exact user preferences
    gen_hdr = f"{tray_hdr}[General]"
    gen_prefs = {
        "disabledStatusNotifiers": "org.kde.yakuake",
        "shownItems": "Insync,org.kde.plasma.volume,org.kde.plasma.networkmanagement",
        "hiddenItems": "Antigravity_status_icon_1,Xwayland Video Bridge,org.kde.plasma.cameraindicator,org.kde.kdeconnect,org.kde.plasma.clipboard,org.kde.plasma.notifications,chrome_status_icon_1@cursor,org.kde.plasma.bluetooth,org.kde.plasma.devicenotifier,org.kde.plasma.brightness",
        "extraItems": "org.kde.plasma.battery,org.kde.plasma.devicenotifier,org.kde.plasma.networkmanagement,org.kde.plasma.printmanager,org.kde.plasma.volume,org.kde.plasma.bluetooth,org.kde.plasma.cameraindicator,org.kde.kdeconnect,org.kde.plasma.clipboard,org.kde.plasma.notifications,org.kde.plasma.brightness,org.kde.kscreen"
    }
    
    if gen_hdr in content:
        lines = content.splitlines(True)
        out_lines = []
        in_gen = False
        seen_keys = set()
        for line in lines:
            stripped = line.strip()
            if stripped == gen_hdr:
                in_gen = True
                out_lines.append(line)
                continue
            elif stripped.startswith("[") and stripped.endswith("]"):
                if in_gen:
                    for k, v in gen_prefs.items():
                        if k not in seen_keys:
                            out_lines.append(f"{k}={v}\n")
                    in_gen = False
                out_lines.append(line)
                continue
            
            if in_gen:
                matched = False
                for k, v in gen_prefs.items():
                    if stripped.startswith(f"{k}="):
                        out_lines.append(f"{k}={v}\n")
                        seen_keys.add(k)
                        matched = True
                        break
                if not matched:
                    out_lines.append(line)
                continue
            out_lines.append(line)
        if in_gen:
            for k, v in gen_prefs.items():
                if k not in seen_keys:
                    out_lines.append(f"{k}={v}\n")
        content = "".join(out_lines)
    else:
        gen_block = f"\n{gen_hdr}\n" + "\n".join(f"{k}={v}" for k, v in gen_prefs.items()) + "\n"
        content += gen_block

# 3. Kickoff Application Menu favorites
kickoff_applet_ids = []
for m in re.finditer(r"^(\[Containments\]\[\d+\]\[Applets\]\[(\d+)\])\s*$", content, re.M):
    applet_id = m.group(2)
    body_end = content.find("\n[", m.end())
    body = content[m.end():body_end if body_end != -1 else len(content)]
    if "plugin=org.kde.plasma.kickoff" in body:
        kickoff_applet_ids.append(applet_id)

activity_ids = []
for m in re.finditer(r"^\[Containments\]\[\d+\]\s*$", content, re.M):
    body_end = content.find("\n[", m.end())
    body = content[m.end():body_end if body_end != -1 else len(content)]
    act_m = re.search(r"^activityId=([a-f0-9\-]+)", body, re.M)
    if act_m and act_m.group(1) not in activity_ids:
        activity_ids.append(act_m.group(1))

if profile == "desktop":
    fav_ordering = "google-chrome.desktop,org.kde.dolphin.desktop,org.kde.discover.desktop,systemsettings.desktop"
else:
    fav_ordering = "antigravity.desktop,cursor.desktop,org.kde.discover.desktop,org.kde.dolphin.desktop,google-chrome.desktop,systemsettings.desktop"

statsrc_path = os.path.expanduser("~/.config/kactivitymanagerd-statsrc")
stats_config = configparser.RawConfigParser()
stats_config.optionxform = str
if os.path.exists(statsrc_path):
    stats_config.read(statsrc_path)

if not kickoff_applet_ids:
    kickoff_applet_ids = ["3"]

for applet_id in kickoff_applet_ids:
    sec_global = f"Favorites-org.kde.plasma.kickoff.favorites.instance-{applet_id}-global"
    if not stats_config.has_section(sec_global):
        stats_config.add_section(sec_global)
    stats_config.set(sec_global, "ordering", fav_ordering)

    for act_id in activity_ids:
        sec_act = f"Favorites-org.kde.plasma.kickoff.favorites.instance-{applet_id}-{act_id}"
        if not stats_config.has_section(sec_act):
            stats_config.add_section(sec_act)
        stats_config.set(sec_act, "ordering", fav_ordering)

os.makedirs(os.path.dirname(statsrc_path), exist_ok=True)
tmp_statsrc = statsrc_path + ".tmp"
with open(tmp_statsrc, "w") as f:
    stats_config.write(f, space_around_delimiters=False)
os.replace(tmp_statsrc, statsrc_path)

tmp_path = path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(content)
os.replace(tmp_path, path)
PY
    fi

    if [[ "$WAS_KACTIVITY_ACTIVE" == true ]]; then
        systemctl --user start plasma-kactivitymanagerd >/dev/null 2>&1 || true
    fi

    if [[ "$WAS_PLASMASHELL_ACTIVE" == true ]]; then
        systemctl --user start plasma-plasmashell >/dev/null 2>&1 || true
        for _ in {1..25}; do
            if qdbus-qt6 org.kde.plasmashell &>/dev/null || qdbus6 org.kde.plasmashell &>/dev/null || qdbus org.kde.plasmashell &>/dev/null; then
                break
            fi
            sleep 0.2
        done
    fi

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
    if command -v qdbus-qt6 &>/dev/null; then
        qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    elif command -v qdbus6 &>/dev/null; then
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    elif command -v qdbus &>/dev/null; then
        qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$PANEL_SCRIPT" >/dev/null 2>&1 || true
    fi

    success "Desktops (DarkestHour), panel layout & task manager configured"
}

# ── Notifications ────────────────────────────────────────────────────────────

configure_notifications() {
    section "KDE Notification Preferences"

    info "Configuring KDE notification rules (silencing Antigravity and Cursor)..."
    local NOTIFY_CONFIG="$HOME/.config/plasmanotifyrc"
    if command -v kwriteconfig6 &>/dev/null; then
        local NOTIFY_DIR; NOTIFY_DIR="$(dirname "$NOTIFY_CONFIG")"
        mkdir -p "$NOTIFY_DIR"
        local TMP_NOTIFY; TMP_NOTIFY="$(mktemp -p "$NOTIFY_DIR" .plasmanotifyrc.tmp.XXXXXX)"
        [[ -f "$NOTIFY_CONFIG" ]] && cp -f "$NOTIFY_CONFIG" "$TMP_NOTIFY"
        for app in antigravity cursor; do
            kwriteconfig6 --file "$TMP_NOTIFY" --group Applications --group "$app" --key Seen true
            kwriteconfig6 --file "$TMP_NOTIFY" --group Applications --group "$app" --key ShowPopups false
            kwriteconfig6 --file "$TMP_NOTIFY" --group Applications --group "$app" --key ShowInHistory false
            kwriteconfig6 --file "$TMP_NOTIFY" --group Applications --group "$app" --key ShowBadges false
        done
        chmod 600 "$TMP_NOTIFY"
        mv -f "$TMP_NOTIFY" "$NOTIFY_CONFIG"
    else
        python3 - "$NOTIFY_CONFIG" << 'PY'
import sys, os, configparser, tempfile

path = sys.argv[1]
dir_path = os.path.dirname(os.path.abspath(path))
os.makedirs(dir_path, exist_ok=True)

config = configparser.RawConfigParser(delimiters=('=',), strict=False)
config.optionxform = str
if os.path.exists(path):
    config.read(path)

for app in ("antigravity", "cursor"):
    sec = f"Applications][{app}"
    if not config.has_section(sec):
        config.add_section(sec)
    config.set(sec, "Seen", "true")
    config.set(sec, "ShowPopups", "false")
    config.set(sec, "ShowInHistory", "false")
    config.set(sec, "ShowBadges", "false")

tmp_fd, tmp_path = tempfile.mkstemp(prefix=".plasmanotifyrc.tmp.", dir=dir_path)
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        config.write(f, space_around_delimiters=False)
    os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, path)
except Exception:
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    raise
PY
    fi
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
