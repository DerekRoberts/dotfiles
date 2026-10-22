#!/usr/bin/env bash
# test-gprune.sh — the gprune bashrc function, against a temp repo with a bare remote.
# Usage: bash scripts/test-gprune.sh
set -euo pipefail

BASHRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/bashrc"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
eval "$(sed -n '/^gprune() {/,/^}/p' "$BASHRC")"

git init -q --bare -b main "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/repo" 2>/dev/null
cd "$TMP/repo"
git config user.name Me; git config user.email me@example.com
echo base > tracked.txt; git add tracked.txt; git commit -q -m init; git push -q origin main
# Gone upstream, not in a worktree: deleted. Gone upstream, held by a clean worktree: kept.
git branch -q gone; git push -q -u origin gone 2>/dev/null
git worktree add -q -b held "$TMP/held"; git -C "$TMP/held" push -q -u origin held 2>/dev/null
git push -q origin --delete gone held 2>/dev/null
git worktree add -q -b clean "$TMP/clean"
git worktree add -q -b spaced "$TMP/clean spaced"
git worktree add -q -b dirty "$TMP/dirty"
echo change > "$TMP/dirty/file.txt"
git worktree add -q -b edited "$TMP/edited"
echo edit >> "$TMP/edited/tracked.txt"

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=1; }
has() { grep -Fxq -- "$1" <<<"$out"; }

before=$(git worktree list --porcelain; git branch -a)
if (cd "$TMP/dirty" && ! gprune >/dev/null 2>&1) && [[ "$(git worktree list --porcelain; git branch -a)" == "$before" ]] &&
  [[ $(git -C "$TMP/dirty" branch --show-current) == dirty ]]; then
  pass "inside a linked worktree: exits without changes"
else fail "inside a linked worktree: exits without changes"; fi

out=$(gprune 2>/dev/null)
if [[ ! -d "$TMP/clean" ]] && has "removed $TMP/clean"; then pass "clean worktree removed"; else fail "clean worktree removed"; fi
if [[ ! -d "$TMP/clean spaced" ]] && has "removed $TMP/clean spaced"; then pass "clean worktree with a space removed"; else fail "clean worktree with a space removed"; fi
if [[ -f "$TMP/dirty/file.txt" ]] && has "kept $TMP/dirty"; then pass "dirty worktree kept"; else fail "dirty worktree kept"; fi
if [[ -d "$TMP/edited" ]] && has "kept $TMP/edited"; then pass "worktree with a tracked edit kept"; else fail "worktree with a tracked edit kept"; fi
if [[ -d "$TMP/repo/.git" ]] && ! has "removed $TMP/repo" && ! has "kept $TMP/repo"; then pass "main checkout kept"; else fail "main checkout kept"; fi
if [[ $(git worktree list | wc -l) -eq 3 ]]; then pass "only main, dirty and edited left"; else fail "only main, dirty and edited left"; fi
if [[ ! -d "$TMP/held" ]] && git show-ref -q --verify refs/heads/held; then
  pass "gone-upstream branch of a removed clean worktree survives the run"
else fail "gone-upstream branch of a removed clean worktree survives the run"; fi
if ! git show-ref -q --verify refs/heads/gone; then pass "gone branch outside a worktree deleted"; else fail "gone branch outside a worktree deleted"; fi

exit "$fails"
