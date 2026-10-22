#!/usr/bin/env bash
# test-gwt-clean.sh — the gwt-clean bashrc function, against a temp repo.
# Usage: bash scripts/test-gwt-clean.sh
set -euo pipefail

BASHRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/bashrc"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
eval "$(sed -n '/^gwt-clean() {/,/^}/p' "$BASHRC")"

git init -q -b main "$TMP/repo"
cd "$TMP/repo"
git config user.name Me; git config user.email me@example.com
git commit -q --allow-empty -m init
git worktree add -q -b clean "$TMP/clean"
git worktree add -q -b dirty "$TMP/dirty"
echo change > "$TMP/dirty/file.txt"

out=$(gwt-clean 2>/dev/null)
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=1; }
if [[ ! -d "$TMP/clean" && $out == *"removed $TMP/clean"* ]]; then pass "clean worktree removed"; else fail "clean worktree removed"; fi
if [[ -f "$TMP/dirty/file.txt" && $out == *"kept $TMP/dirty (has changes)"* ]]; then pass "dirty worktree kept"; else fail "dirty worktree kept"; fi
if [[ -d "$TMP/repo/.git" && $out != *"$TMP/repo"* ]]; then pass "main checkout kept"; else fail "main checkout kept"; fi
if [[ $(git worktree list | wc -l) -eq 2 ]]; then pass "only main and dirty left"; else fail "only main and dirty left"; fi

exit "$fails"
