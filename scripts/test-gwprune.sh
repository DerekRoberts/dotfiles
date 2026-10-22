#!/usr/bin/env bash
# test-gwprune.sh — the gwprune bashrc function, against a temp repo.
# Usage: bash scripts/test-gwprune.sh
set -euo pipefail

BASHRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/bashrc"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
eval "$(sed -n '/^gwprune() {/,/^}/p' "$BASHRC")"

git init -q -b main "$TMP/repo"
cd "$TMP/repo"
git config user.name Me; git config user.email me@example.com
echo base > tracked.txt; git add tracked.txt; git commit -q -m init
git worktree add -q -b clean "$TMP/clean"
git worktree add -q -b dirty "$TMP/dirty"
echo change > "$TMP/dirty/file.txt"
git worktree add -q -b spaced "$TMP/clean spaced"
git worktree add -q -b edited "$TMP/edited"
echo edit >> "$TMP/edited/tracked.txt"

out=$(gwprune 2>/dev/null)
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=1; }
has() { grep -Fxq -- "$1" <<<"$out"; }
if [[ ! -d "$TMP/clean" ]] && has "removed $TMP/clean"; then pass "clean worktree removed"; else fail "clean worktree removed"; fi
if [[ ! -d "$TMP/clean spaced" ]] && has "removed $TMP/clean spaced"; then pass "clean worktree with a space removed"; else fail "clean worktree with a space removed"; fi
if [[ -f "$TMP/dirty/file.txt" ]] && has "kept $TMP/dirty"; then pass "dirty worktree kept"; else fail "dirty worktree kept"; fi
if [[ -d "$TMP/edited" ]] && has "kept $TMP/edited"; then pass "worktree with a tracked edit kept"; else fail "worktree with a tracked edit kept"; fi
if [[ -d "$TMP/repo/.git" ]] && ! has "removed $TMP/repo" && ! has "kept $TMP/repo"; then pass "main checkout kept"; else fail "main checkout kept"; fi
if [[ $(git worktree list | wc -l) -eq 3 ]]; then pass "only main, dirty and edited left"; else fail "only main, dirty and edited left"; fi

exit "$fails"
