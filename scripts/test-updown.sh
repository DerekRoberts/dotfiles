#!/usr/bin/env bash
# test-updown.sh — updown's version checks, step timing and parallel jobs,
# with every external command stubbed. No network, no root.
# Usage: bash scripts/test-updown.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0

ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=1; }
# check <name> <command...> — pass when the command succeeds
check() { local name="$1"; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
# refute <name> <command...> — pass when the command fails
refute() { local name="$1"; shift; if "$@"; then fail "$name"; else ok "$name"; fi; }
# contains/lacks <name> <text> — pass when $out has / doesn't have the text
contains() { if grep -qF -- "$2" <<< "$out"; then ok "$1"; else fail "$1"; fi; }
lacks()    { if grep -qF -- "$2" <<< "$out"; then fail "$1"; else ok "$1"; fi; }

# ── lib.sh helpers ───────────────────────────────────────────────────────────

# shellcheck source=scripts/lib.sh
. "$REPO/scripts/lib.sh"

check "current when versions match"        version_is_current 1.2.3 1.2.3
refute "not current when newer exists"     version_is_current 1.2.3 1.2.4
refute "not current when lookup failed"    version_is_current 1.2.3 unknown
refute "not current when latest is empty"  version_is_current 1.2.3 ""
refute "not current when not installed"    version_is_current none 1.2.3


out="$(LOG_PREFIX="[x] " timed_step demo true)"
check "timed_step prints elapsed" grep -qxE '\[x\] ⏱ demo: [0-9]+s' <<< "$out"
rc=0; out="$(timed_step demo bash -c 'exit 3')" || rc=$?
check "timed_step keeps exit status" test "$rc" -eq 3
contains "timed_step reports failure" "⏱ demo: 0s (exit 3)"
set +e; (set -e; timed_step demo eval 'false; echo "not reached"') > "$TMP/out"; set -e; out="$(cat "$TMP/out")"
lacks "timed_step keeps set -e inside the step" "not reached"
contains "timed_step times a set -e stop" "(exit 1)"

out="$(spawn_step "[a] " bash -c 'echo one; echo two >&2'; spawn_step "[b] " echo three; wait_steps)"
contains "spawn_step prefixes stdout"        "[a] one"
contains "spawn_step prefixes stderr"        "[a] two"
contains "spawn_step prefixes each job"      "[b] three"
rc=0; out="$( { spawn_step "[a] " true; spawn_step "[b] " false; wait_steps; } 2>&1)" || rc=$?
check "wait_steps fails when any step fails" test "$rc" -eq 1
contains "wait_steps names the failed step" "[b] ⚠ step failed"
start="$(date +%s)"
spawn_step "[a] " sleep 2; spawn_step "[b] " sleep 2; wait_steps
check "spawned steps run at the same time" test $(( $(date +%s) - start )) -lt 4

# ── updown.sh end to end, stubbed ────────────────────────────────────────────

FAKE_HOME="$TMP/home"; DF="$TMP/dotfiles"; BIN="$TMP/bin"; LOG="$TMP/calls"
mkdir -p "$FAKE_HOME/.local/bin" "$DF/scripts/setup" "$BIN"
cp "$REPO/scripts/lib.sh" "$DF/scripts/lib.sh"
mkdir -p "$TMP/inst"   # no setup.sh one level up, so DOTFILES_DIR is used
cp "$REPO/scripts/updown.sh" "$TMP/inst/updown"
cat > "$DF/scripts/setup/dev.sh" << 'STUB'
#!/usr/bin/env bash
echo "tools stub UPDATE=$UPDATE"
STUB

stub() { printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$LOG" "${2:-}" > "$BIN/$1"; chmod +x "$BIN/$1"; }
stub rpm-ostree
cat >> "$BIN/rpm-ostree" << 'STUB'
if [[ "$*" == "upgrade --check" ]]; then
    case "${RPMOSTREE_CHECK:-update}" in
        update) printf '%s\n' 'AvailableUpdate:' '        Version: 44.20261011.0 (2026-10-11T04:00:00Z)' ;;
        none)   echo 'No updates available.'; exit 77 ;;
        fail)   echo 'error: cannot reach the remote'; exit 1 ;;
    esac
fi
STUB
stub flatpak
cat >> "$BIN/flatpak" << 'STUB'
[[ "${FAIL_FLATPAK:-0}" -eq 0 ]] || exit 1
STUB
stub restorecon
stub update-antigravity 'echo "hub stub"'
stub systemctl
cat >> "$BIN/systemctl" << 'STUB'
# Snapshot the log at the moment poweroff would run.
cp "$HOME/.local/state/dotfiles/updown.log" "$HOME/log-at-poweroff"
STUB
stub sleep   # the 3 s shutdown countdown
stub curl 'exit 7'   # nothing reaches the network

run_updown() {
    env -i HOME="$FAKE_HOME" PATH="$BIN:/usr/bin:/bin" DOTFILES_DIR="$DF" \
        FAIL_FLATPAK="${FAIL_FLATPAK:-0}" \
        RPMOSTREE_CHECK="${RPMOSTREE_CHECK:-update}" bash "$TMP/inst/updown" "${@:---background}" 2>&1
}

rc=0; out="$(run_updown)" || rc=$?
check "updown exits 0" test "$rc" -eq 0
contains "rpm-ostree timed"          "[updown] ⏱ rpm-ostree: "
contains "flatpak user in parallel"  "[updown] [flatpak-user] ⏱ flatpak-user: "
contains "flatpak system in parallel" "[updown] [flatpak-system] ⏱ flatpak-system: "
contains "tools step prefixed"       "[updown] [tools] tools stub UPDATE=1"
contains "hub step prefixed"         "[updown] [antigravity] hub stub"
contains "parallel wall time"        "[updown] ⏱ parallel steps: "
contains "restorecon timed"          "[updown] ⏱ restorecon: "
contains "total printed"             "[updown] ⏱ total: "
refute "no shutdown in background" grep -q "^systemctl" "$LOG"
order="$(grep -nE '⏱ (rpm-ostree|parallel steps|restorecon|total):' <<< "$out" | cut -d: -f1 | paste -sd' ')"
check "rpm-ostree first, restorecon after the parallel steps" \
    test "$order" = "$(tr ' ' '\n' <<< "$order" | sort -n | paste -sd' ')" -a "$(wc -w <<< "$order")" -eq 4


# A failed flatpak update warns and continues, as before: the run still
# succeeds and restorecon still runs.
: > "$LOG"
rc=0; out="$(FAIL_FLATPAK=1 run_updown)" || rc=$?
check    "failed flatpak update is not fatal" test "$rc" -eq 0
contains "failed flatpak update warns"        "[updown] [flatpak-user] ⚠ Flatpak user update failed — continuing"
check    "restorecon runs after a failed flatpak update" grep -q "^restorecon" "$LOG"

# rpm-ostree: check first, stage only when there is an update.
: > "$LOG"; out="$(run_updown)"
contains "rpm-ostree update: staging version logged" "[updown] rpm-ostree: staging 44.20261011.0"
check    "rpm-ostree update: upgrade staged"         grep -qx "rpm-ostree upgrade --quiet" "$LOG"
: > "$LOG"; out="$(RPMOSTREE_CHECK=none run_updown)"
contains "rpm-ostree no update: logged"              "[updown] rpm-ostree: no update"
refute   "rpm-ostree no update: no upgrade"          grep -qx "rpm-ostree upgrade --quiet" "$LOG"
: > "$LOG"; rc=0; out="$(RPMOSTREE_CHECK=fail run_updown)" || rc=$?
check    "rpm-ostree check failed: run still exits 0" test "$rc" -eq 0
contains "rpm-ostree check failed: fallback logged"  "[updown] ⚠ rpm-ostree: update check failed (exit 1) — running the upgrade anyway"
check    "rpm-ostree check failed: upgrade still runs" grep -qx "rpm-ostree upgrade --quiet" "$LOG"
check    "rpm-ostree check runs before the upgrade" \
    test "$(grep -n '^rpm-ostree' "$LOG" | cut -d: -f2- | paste -sd'|')" = "rpm-ostree upgrade --check|rpm-ostree upgrade --quiet"

# ── Run log ──────────────────────────────────────────────────────────────────

RUNLOG="$FAKE_HOME/.local/state/dotfiles/updown.log"
check  "run log written"                 test -s "$RUNLOG"
check  "run log has the total"           grep -qF "[updown] ⏱ total: " "$RUNLOG"
check  "run log has per-step timing"     grep -qF "[updown] [flatpak-user] ⏱ flatpak-user: " "$RUNLOG"
check  "run log has stderr lines"        grep -qF "⚠ rpm-ostree: update check failed" "$RUNLOG"
refute "every run log line is timestamped" \
    grep -vqE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4} ' "$RUNLOG"
lacks  "console output has no timestamps" "$(date +%Y)-"

# Rotation: mark each run, then check the newest five are kept in order.
for n in 1 2 3 4 5 6; do
    run_updown > /dev/null
    echo "marker run $n" >> "$RUNLOG"
done
check  "rotation keeps updown.log"       grep -q "marker run 6" "$RUNLOG"
check  "rotation keeps updown.log.1"     grep -q "marker run 5" "$RUNLOG.1"
check  "rotation keeps updown.log.4"     grep -q "marker run 2" "$RUNLOG.4"
refute "rotation keeps no more than 5"   test -e "$RUNLOG.5"

# An interactive run ends in shutdown: the log must be complete and on disk
# before poweroff runs.
rm -f "$FAKE_HOME/log-at-poweroff"
rc=0; out="$(run_updown --shutdown)" || rc=$?
check "shutdown run exits 0"             test "$rc" -eq 0
check "poweroff ran"                     test -f "$FAKE_HOME/log-at-poweroff"
check "log complete before poweroff: total" \
    grep -qF "[updown] ⏱ total: " "$FAKE_HOME/log-at-poweroff"
check "log complete before poweroff: shutdown notice" \
    grep -qF "Shutting down system in 3 seconds" "$FAKE_HOME/log-at-poweroff"
contains "console still shows the shutdown notice" "Shutting down system in 3 seconds"

# Logging problems never fail the run.
mv "$FAKE_HOME/.local/state/dotfiles" "$TMP/state-saved"
touch "$FAKE_HOME/.local/state/dotfiles"   # a file where the log dir should be
rc=0; out="$(run_updown)" || rc=$?
rm -f "$FAKE_HOME/.local/state/dotfiles"; mv "$TMP/state-saved" "$FAKE_HOME/.local/state/dotfiles"
check    "unwritable log dir does not fail the run" test "$rc" -eq 0
contains "unwritable log dir still prints the total" "[updown] ⏱ total: "
contains "unwritable log dir is reported" "continuing without a log file"

# ── dev.sh --tools: one prefixed, timed job per tool ─────────────────────────

rc=0
out="$(env -i HOME="$FAKE_HOME" PATH="$BIN:/usr/bin:/bin" BIN_DIR="$TMP/tools" UPDATE=1 \
    bash "$REPO/scripts/setup/dev.sh" --tools 2>&1)" || rc=$?
check "dev.sh --tools fails when a lookup fails" test "$rc" -eq 1
for t in jq gh gitleaks docker-compose shellcheck actionlint uv oc; do
    contains "dev.sh --tools runs $t as its own job" "[$t] ⏱ $t: "
done
contains "dev.sh --tools keeps per-tool warnings" "[gh]   ⚠ Could not resolve latest release tag for cli/cli"

# ── Antigravity URL parsing ──────────────────────────────────────────────────

mock_html="const r = \`https://storage.googleapis.com/antigravity-public/antigravity-hub/\${e}-\${t}\`;return n===\`linux-x64\`?\`\${r}/linux-x64/Antigravity.tar.gz\`:null; https://storage.googleapis.com/antigravity-public/antigravity-hub/2.23.1-6348059836284928/linux-x64/Antigravity.tar.gz"
parsed_url="$(grep -oE 'https://storage\.googleapis\.com/antigravity-public/antigravity-hub/[0-9A-Za-z._-]+/linux-x64/Antigravity\.tar\.gz' <<< "$mock_html" | head -n 1 || true)"
check "antigravity URL parsing ignores JS template literals" test "$parsed_url" = "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.23.1-6348059836284928/linux-x64/Antigravity.tar.gz"

mock_template="const r = \`https://storage.googleapis.com/antigravity-public/antigravity-hub/\${e}-\${t}\`;"
no_url="$(grep -oE 'https://storage\.googleapis\.com/antigravity-public/antigravity-hub/[0-9A-Za-z._-]+/linux-x64/Antigravity\.tar\.gz' <<< "$mock_template" | head -n 1 || true)"
check "antigravity URL parsing rejects JS template without release" test -z "$no_url"

# ── Every curl on the updown path has both timeouts ──────────────────────────

missing="$(grep -nE '(^|[^[:alnum:]_-])curl ' "$REPO/scripts/updown.sh" "$REPO/scripts/update-antigravity.sh" "$REPO/scripts/lib.sh" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -vE -- '--connect-timeout [0-9]+ --max-time [0-9]+|CURL_(META|SCRIPT|FILE)' || true)"
check "curl calls set --connect-timeout and --max-time" test -z "$missing"
[[ -z "$missing" ]] || printf '%s\n' "$missing"

[[ -n "${DEBUG:-}" ]] && printf "%s\n" "$out"
exit "$fails"
