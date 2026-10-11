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

STUBS="$TMP/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/npm" << 'STUB'
#!/usr/bin/env bash
case "$1" in
    list) printf '%s\n' "$HOME/.nvm/versions/node/v22/lib" "└── @kilocode/cli@${KILO_INSTALLED:-1.2.3}" ;;
    view) printf '%s\n' "${KILO_LATEST:-1.2.3}" ;;
    prefix) printf '%s\n' "$HOME/.nvm/versions/node/v22" ;;
    -v) echo 11.0.0 ;;
    install) touch "$HOME/kilo-installed" ;;
esac
STUB
chmod +x "$STUBS/npm"
PATH_SAVED="$PATH"; PATH="$STUBS:$PATH"
check  "kilo installed version parsed"   test "$(kilo_cli_version)" = 1.2.3
check  "kilo latest version read"        test "$(KILO_LATEST=2.0.1 kilo_cli_latest_version)" = 2.0.1
refute "kilo latest rejects non-versions" env KILO_LATEST="npm error" bash -c ". '$REPO/scripts/lib.sh'; kilo_cli_latest_version"
PATH="$PATH_SAVED"

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
mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/.nvm/bin" "$DF/scripts/setup" "$BIN"
cp "$REPO/scripts/lib.sh" "$DF/scripts/lib.sh"
mkdir -p "$TMP/inst"   # no setup.sh one level up, so DOTFILES_DIR is used
cp "$REPO/scripts/updown.sh" "$TMP/inst/updown"
cat > "$DF/scripts/setup/dev.sh" << 'STUB'
#!/usr/bin/env bash
echo "tools stub UPDATE=$UPDATE"
STUB

stub() { printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$LOG" "${2:-}" > "$BIN/$1"; chmod +x "$BIN/$1"; }
stub rpm-ostree
stub flatpak
stub restorecon
stub update-antigravity 'echo "hub stub"'
stub systemctl
stub curl 'exit 7'   # nothing reaches the network
cp "$STUBS/npm" "$FAKE_HOME/.nvm/bin/npm"
cat > "$FAKE_HOME/.nvm/nvm.sh" << 'STUB'
export PATH="$NVM_DIR/bin:$PATH"
nvm() { return 0; }
STUB

run_updown() {
    env -i HOME="$FAKE_HOME" PATH="$BIN:/usr/bin:/bin" DOTFILES_DIR="$DF" \
        KILO_LATEST="${KILO_LATEST:-1.2.3}" bash "$TMP/inst/updown" --background 2>&1
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
contains "kilo current, skipped"     "[updown] [kilo] ✓ Kilo CLI is up to date (1.2.3)"
refute "kilo current, no reinstall" test -e "$FAKE_HOME/kilo-installed"
refute "no shutdown in background" grep -q "^systemctl" "$LOG"
order="$(grep -nE '⏱ (rpm-ostree|parallel steps|restorecon|total):' <<< "$out" | cut -d: -f1 | paste -sd' ')"
check "rpm-ostree first, restorecon after the parallel steps" \
    test "$order" = "$(tr ' ' '\n' <<< "$order" | sort -n | paste -sd' ')" -a "$(wc -w <<< "$order")" -eq 4

out="$(KILO_LATEST=1.2.4 run_updown)"
check "kilo outdated, reinstalled" test -e "$FAKE_HOME/kilo-installed"
contains "kilo update logged" "Updating Kilo CLI (1.2.3 -> 1.2.4)"

# ── dev.sh --tools: one prefixed, timed job per tool ─────────────────────────

rc=0
out="$(env -i HOME="$FAKE_HOME" PATH="$BIN:/usr/bin:/bin" BIN_DIR="$TMP/tools" UPDATE=1 \
    bash "$REPO/scripts/setup/dev.sh" --tools 2>&1)" || rc=$?
check "dev.sh --tools fails when a lookup fails" test "$rc" -eq 1
for t in jq gh gitleaks docker-compose shellcheck actionlint uv oc; do
    contains "dev.sh --tools runs $t as its own job" "[$t] ⏱ $t: "
done
contains "dev.sh --tools keeps per-tool warnings" "[gh]   ⚠ Could not resolve latest release tag for cli/cli"

# ── Every curl on the updown path has both timeouts ──────────────────────────

missing="$(grep -nE '(^|[^[:alnum:]_-])curl ' "$REPO/scripts/updown.sh" "$REPO/scripts/update-antigravity.sh" "$REPO/scripts/lib.sh" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -vE -- '--connect-timeout [0-9]+ --max-time [0-9]+|CURL_(META|SCRIPT|FILE)' || true)"
check "curl calls set --connect-timeout and --max-time" test -z "$missing"
[[ -z "$missing" ]] || printf '%s\n' "$missing"

[[ -n "${DEBUG:-}" ]] && printf "%s\n" "$out"
exit "$fails"
