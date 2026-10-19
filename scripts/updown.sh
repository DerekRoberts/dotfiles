#!/usr/bin/env bash
# updown — Workstation silent maintenance
# Stages rpm-ostree upgrade, updates flatpaks, updates third-party binaries,
# and updates the Antigravity hub, Cursor, and Grok Bot.
#
# Usage:
#   updown                 — run updates then power off (default / interactive)
#   updown --background, -b — run updates in the background without power off
#
# rpm-ostree runs first on its own, the independent updates then run in
# parallel, and restorecon runs last. Each step prints its elapsed time.
# Each run is also logged to ~/.local/state/dotfiles/updown.log (last 5 kept).
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
CURL_FILE=(--connect-timeout 10 --max-time 900)

# ── Run log ──────────────────────────────────────────────────────────────────
# Every run, background or interactive, is also written to UPDOWN_LOG with a
# timestamp on each line, so output survives a shutdown. The last 5 runs are
# kept (updown.log, updown.log.1 ... .4). Logging problems never fail the run.

UPDOWN_LOG="$HOME/.local/state/dotfiles/updown.log"
LOG_PIDS=()
LOG_FD=""

open_log() {
    mkdir -p "$(dirname "$UPDOWN_LOG")" 2>/dev/null || return 1
    rotate_logs "$UPDOWN_LOG" 5 2>/dev/null || true
    : > "$UPDOWN_LOG" 2>/dev/null || return 1
    # One writer stamps lines into the file. Console stdout and stderr each
    # go through their own tee, so the console stays as it was. tee -p keeps
    # writing to the console if the log side goes away.
    exec {CONSOLE_OUT}>&1 {CONSOLE_ERR}>&2
    exec {LOG_FD}> >(set +e; stamp_lines >> "$UPDOWN_LOG" 2>/dev/null; cat > /dev/null)
    LOG_PIDS+=("$!")
    exec > >(tee -p "/dev/fd/$LOG_FD" 2>/dev/null)
    LOG_PIDS+=("$!")
    exec 2> >(tee -p "/dev/fd/$LOG_FD" 1>&"$CONSOLE_ERR" 2>/dev/null)
    LOG_PIDS+=("$!")
}

# Close the tees and the writer, wait for them to drain, then sync the log to
# disk. Safe to call more than once.
close_log() {
    local pid i
    [[ -n "$LOG_FD" ]] || return 0
    exec 1>&"$CONSOLE_OUT" 2>&"$CONSOLE_ERR"
    exec {LOG_FD}>&-
    LOG_FD=""
    for pid in "${LOG_PIDS[@]}"; do
        # Bounded wait: a stuck writer must not hold up shutdown.
        for (( i = 0; i < 50; i++ )); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
        fi
    done
    LOG_PIDS=()
    sync -f "$UPDOWN_LOG" 2>/dev/null || sync 2>/dev/null || true
}

open_log || warn "Cannot write $UPDOWN_LOG — continuing without a log file"

UPDOWN_START="$(date +%s)"
report_total() {
    info "⏱ total: $(( $(date +%s) - UPDOWN_START ))s"
}
trap 'report_total; close_log' EXIT

# ── Steps ────────────────────────────────────────────────────────────────────

# 1. rpm-ostree. Stages the update; does NOT reboot automatically.
# On Kinoite, apply takes effect on next reboot (user-controlled).
# Check first and stage only when there is an update. `upgrade --check` exits
# 77 when there is nothing new; any other failure falls back to the upgrade.
step_rpm_ostree() {
    local out rc=0 version
    info "Checking for an rpm-ostree update..."
    out="$(rpm-ostree upgrade --check 2>&1)" || rc=$?
    if [[ "$rc" -eq 77 ]] || { [[ "$rc" -eq 0 ]] && grep -qi 'no updates available' <<< "$out"; }; then
        info "rpm-ostree: no update"
        return 0
    elif [[ "$rc" -eq 0 ]]; then
        version="$(awk '/^[[:space:]]*Version:/ {print $2; exit}' <<< "$out")"
        info "rpm-ostree: staging ${version:-update}"
    else
        [[ -z "$out" ]] || printf '%s\n' "$out"
        warn "rpm-ostree: update check failed (exit $rc) — running the upgrade anyway"
    fi

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
# installations).
info "Running update steps in parallel..."
PARALLEL_START="$(date +%s)"
bg_step flatpak-user   step_flatpak_user
bg_step flatpak-system step_flatpak_system
bg_step antigravity    step_antigravity
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
if [[ "$SHUTDOWN" -eq 1 ]]; then
    echo "Shutting down system in 3 seconds (Ctrl+C to cancel)..."
fi
# Flush and sync the log before anything can power the machine off.
trap - EXIT
close_log

if [[ "$SHUTDOWN" -eq 1 ]]; then
    sleep 3
    systemctl poweroff
fi
