#!/usr/bin/env bash
# updown — Workstation silent maintenance
# Stages rpm-ostree upgrade, updates flatpaks, updates third-party binaries,
# and updates Antigravity CLI + hub, Kilo CLI, Cursor CLI, Cursor, and Grok Bot.
#
# Usage:
#   updown                 — run updates then power off (default / interactive)
#   updown --background, -b — run updates in the background without power off
#
# rpm-ostree runs first on its own, the independent updates then run in
# parallel, and restorecon runs last. Each step prints its elapsed time.
#
# The systemd user service (config/systemd/dotfiles-update.service) calls
# this script with --background on graphical session start (at most once per 23h).

set -euo pipefail

SHUTDOWN=1

for arg in "$@"; do
    case "$arg" in
        --background|-b|--no-shutdown|-n)
            SHUTDOWN=0
            ;;
        --shutdown|-s)
            SHUTDOWN=1
            ;;
        --help|-h)
            echo "Usage: updown [options]"
            echo "  (default)            Run updates and power off"
            echo "  --background, -b     Run updates in background without power off"
            echo "  --help, -h           Show this help"
            exit 0
            ;;
    esac
done

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
if [[ -n "$SCRIPT_PATH" && -f "$(dirname "$SCRIPT_PATH")/../setup.sh" ]]; then
    DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
else
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Repos/dotfiles}"
fi
# Locate helper scripts in the clone. Never git-pull this repository from the
# updater: a remote change would become an execution path at login.
DOTFILES_PROFILE="${DOTFILES_PROFILE:-dev}"

# systemd user units often omit ~/.local/bin (where jq, gh, oc live)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# updown is installed to ~/.local/bin, so the clone it came from may be gone.
if [[ ! -f "$DOTFILES_DIR/scripts/lib.sh" ]]; then
    echo "[updown] ⚠ Cannot find $DOTFILES_DIR/scripts/lib.sh — set DOTFILES_DIR to the clone." >&2
    exit 1
fi
# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

# This runs unattended from a systemd user unit, so prefix every line to make
# the journal readable. Parallel jobs clear LOG_PREFIX because spawn_step
# already puts "[updown] [step] " in front of everything they print.
LOG_PREFIX="[updown] "
info()    { echo "${LOG_PREFIX}$*"; }
success() { echo "${LOG_PREFIX}✓ $*"; }
warn()    { echo "${LOG_PREFIX}⚠ $*" >&2; }

# Timeouts for every curl here, so one stalled host can't hold up the run.
CURL_META=(--connect-timeout 10 --max-time 20)
CURL_SCRIPT=(--connect-timeout 10 --max-time 60)
CURL_FILE=(--connect-timeout 10 --max-time 900)

UPDOWN_START="$(date +%s)"
report_total() {
    info "⏱ total: $(( $(date +%s) - UPDOWN_START ))s"
}
trap report_total EXIT

# ── Steps ────────────────────────────────────────────────────────────────────

# 1. rpm-ostree. Stages the update; does NOT reboot automatically.
# On Kinoite, apply takes effect on next reboot (user-controlled).
step_rpm_ostree() {
    info "Staging rpm-ostree upgrade..."
    if rpm-ostree upgrade --quiet 2>&1; then
        success "rpm-ostree upgrade staged (reboot when ready to apply)"
    else
        warn "rpm-ostree upgrade failed or nothing to do — continuing"
    fi
}

# 2. Flatpak. User and system installations keep separate repos and locks.
step_flatpak_user() {
    info "Updating user Flatpaks..."
    if flatpak update --user -y --noninteractive 2>&1; then
        success "User Flatpaks updated"
    else
        warn "Flatpak user update failed — continuing"
    fi
}

step_flatpak_system() {
    info "Updating system Flatpaks..."
    if flatpak update --system -y --noninteractive 2>&1; then
        success "System Flatpaks updated"
    else
        # Not fatal if user is not in wheel or polkit denies silent system update
        info "System Flatpak update skipped or completed"
    fi
}

# 3. Antigravity Hub. Writes ~/.local/bin/antigravity and its own stamp.
step_antigravity() {
    local updater=""
    if command -v update-antigravity &>/dev/null; then
        updater="update-antigravity"
    elif [[ -x "$HOME/.local/bin/update-antigravity" ]]; then
        updater="$HOME/.local/bin/update-antigravity"
    elif [[ -f "$DOTFILES_DIR/scripts/update-antigravity.sh" ]]; then
        updater="$DOTFILES_DIR/scripts/update-antigravity.sh"
    fi

    if [[ -n "$updater" ]]; then
        bash "$updater" || warn "Antigravity hub update exited with error"
    else
        info "update-antigravity not found — skipping"
    fi
}

# 4. agy CLI. Re-running the install script is its update mechanism.
step_agy() {
    local agy_bin="${HOME}/.local/bin/agy" latest current
    if [[ ! -x "$agy_bin" ]]; then
        info "agy CLI not installed — skipping"
        return 0
    fi
    info "Checking agy CLI for updates..."
    latest=$(curl -fsSL "${CURL_META[@]}" https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json | jq -r .version 2>/dev/null || echo "unknown")
    current=$("$agy_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "none")

    if version_is_current "$current" "$latest"; then
        success "agy CLI is up to date ($current)"
    else
        info "Updating agy CLI ($current -> $latest)..."
        if curl -fsSL "${CURL_SCRIPT[@]}" https://antigravity.google/cli/install.sh | bash 2>&1; then
            success "agy CLI updated"
        else
            warn "agy update failed — continuing"
        fi
    fi
}

# 5. Kilo Code CLI (nvm npm global). Only step that touches npm.
step_kilo() {
    local latest current
    if ! { load_nvm && kilo_cli_installed; }; then
        info "Kilo CLI not installed — skipping"
        return 0
    fi
    info "Checking Kilo CLI for updates..."
    latest="$(kilo_cli_latest_version || echo unknown)"
    current="$(kilo_cli_version || echo none)"

    if version_is_current "$current" "$latest"; then
        success "Kilo CLI is up to date ($current)"
    else
        info "Updating Kilo CLI ($current -> $latest)..."
        if install_kilo_cli_pkg 2>&1; then
            success "Kilo CLI updated ($(kilo --version 2>/dev/null || echo ok))"
        else
            warn "Kilo CLI update failed — continuing"
        fi
    fi
}

# 5b. Cursor CLI (agent / cursor-agent). Upstream update command: agent update
# https://cursor.com/docs/cli/installation
step_cursor_cli() {
    local bin=""
    if [[ -x "${HOME}/.local/bin/agent" ]]; then
        bin="${HOME}/.local/bin/agent"
    elif [[ -x "${HOME}/.local/bin/cursor-agent" ]]; then
        bin="${HOME}/.local/bin/cursor-agent"
    fi
    if [[ -n "$bin" ]]; then
        info "Updating Cursor CLI..."
        if "$bin" update; then
            success "Cursor CLI updated ($("$bin" --version 2>/dev/null || echo ok))"
        else
            warn "Cursor CLI update failed — continuing"
        fi
    else
        info "Cursor CLI not installed — skipping"
    fi
}

# 6. Cursor. Writes cursor.AppImage and the cursor.url stamp.
step_cursor() {
    local cursor_bin="${HOME}/.local/bin/cursor.AppImage"
    local stamp_file="${HOME}/.local/share/dotfiles/cursor.url"
    local latest_url
    if [[ ! -x "$cursor_bin" ]]; then
        info "Cursor not installed — skipping"
        return 0
    fi
    info "Checking Cursor for updates..."
    latest_url="$(cursor_latest_url || true)"

    if [[ -z "$latest_url" ]]; then
        warn "Cursor URL missing or outside $CURSOR_URL_PREFIX — skipping update"
    elif [[ -f "$stamp_file" ]] && [[ "$(cat "$stamp_file")" == "$latest_url" ]]; then
        success "Cursor is up to date"
    else
        info "Updating Cursor..."
        if curl -L -fsS "${CURL_FILE[@]}" "$latest_url" -o "${cursor_bin}.tmp"; then
            mv "${cursor_bin}.tmp" "$cursor_bin"
            chmod +x "$cursor_bin"
            mkdir -p "$(dirname "$stamp_file")"
            echo "$latest_url" > "$stamp_file"
            success "Cursor updated"
        else
            warn "Cursor update failed (download error)"
            rm -f "${cursor_bin}.tmp"
        fi
    fi
}

# 6b. Grok Bot (user-dropped AppImage in ~/Downloads). Writes grok-bot.AppImage,
# its sha256 stamp and environment.d/appimage.conf.
step_grok() {
    if [[ ! -x "${HOME}/.local/bin/grok-bot.AppImage" ]]; then
        info "Grok Bot not installed — skipping"
        return 0
    fi
    install_appimage_extract_env || warn "Grok Bot session env failed — continuing"
    info "Checking Grok Bot AppImage from ~/Downloads..."
    if UPDATE=1 stage_grok_bot_appimage; then
        success "Grok Bot AppImage staged"
    else
        warn "Grok Bot stage failed — continuing"
    fi
}

# 7. Standalone Dev CLI Tools (includes oc). dev.sh runs its per-tool lookups
# in parallel itself; each tool writes only its own binaries and stamp.
step_tools() {
    if [[ -f "$DOTFILES_DIR/scripts/setup/dev.sh" ]]; then
        info "Checking standalone CLI tools for updates..."
        UPDATE=1 bash "$DOTFILES_DIR/scripts/setup/dev.sh" --tools || warn "CLI tools update encountered warnings"
    fi
}

# 8. SELinux context fix. restorecon is always present on Kinoite (part of the
# base image). Fixes SELinux labels on any extracted binaries in ~/.local/bin.
step_restorecon() {
    info "Restoring SELinux contexts on ~/.local/bin..."
    if command -v restorecon &>/dev/null; then
        restorecon -R "${HOME}/.local/bin" 2>&1 | grep -v "^$" || true
        success "SELinux contexts restored"
    else
        info "restorecon not available — skipping (not on SELinux system?)"
    fi
}

# Background step: timed, with "[updown] [name] " on every line.
quiet_timed() {
    local LOG_PREFIX=""
    timed_step "$@"
}
bg_step() {
    spawn_step "[updown] [$1] " quiet_timed "$@"
}

# ── Run ──────────────────────────────────────────────────────────────────────

# rpm-ostree first and alone: it is the slowest step and the only system-level
# transaction, so nothing else competes with it.
timed_step rpm-ostree step_rpm_ostree

# Everything below is independent: each step writes only its own files, and no
# two share a package manager (flatpak --user and --system use separate
# installations; only Kilo uses npm).
info "Running update steps in parallel..."
PARALLEL_START="$(date +%s)"
bg_step flatpak-user   step_flatpak_user
bg_step flatpak-system step_flatpak_system
bg_step antigravity    step_antigravity
bg_step agy            step_agy
bg_step kilo           step_kilo
bg_step cursor-cli     step_cursor_cli
bg_step cursor         step_cursor
bg_step grok           step_grok
bg_step tools          step_tools
if ! wait_steps; then
    warn "One or more update steps failed"
    exit 1
fi
info "⏱ parallel steps: $(( $(date +%s) - PARALLEL_START ))s"

# After everything, so it relabels whatever the steps installed.
timed_step restorecon step_restorecon

# ── 9. Shutdown ──────────────────────────────────────────────────────────────

echo ""
echo "✅ Maintenance complete."
report_total
trap - EXIT

if [[ "$SHUTDOWN" -eq 1 ]]; then
    echo "Shutting down system in 3 seconds (Ctrl+C to cancel)..."
    sleep 3
    systemctl poweroff
fi
