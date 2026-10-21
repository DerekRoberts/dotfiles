#!/usr/bin/env bash
# test-pre-push.sh — the pre-push hook, as examples.
# Usage: bash scripts/test-pre-push.sh
set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/hooks/pre-push"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
Z=0000000000000000000000000000000000000000
fails=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init -q --bare -b main "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/w" 2>/dev/null
cd "$TMP/w"
git config user.name Me; git config user.email me@example.com
git commit -q --allow-empty -m init; git push -q origin main
c() { git commit -q --allow-empty -m "$1" "${@:2}"; git rev-parse HEAD; }

# expect <name> <0|1> <local_sha> <remote_ref> <remote_sha>
expect() {
    if printf '%s %s %s %s\n' "${6:-refs/heads/x}" "$3" "$4" "$5" | bash "$HOOK" origin >/dev/null 2>&1; then got=0; else got=1; fi
    if [[ "$got" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1 (exit $got)"; fails=1; fi
}

git checkout -q -b feat/a
a1=$(c a1)
expect "new branch allowed" 0 "$a1" refs/heads/feat/a "$Z"
a2=$(c a2)
expect "fast-forward allowed" 0 "$a2" refs/heads/feat/a "$a1"
git checkout -q -b feat/b "$a1"; b2=$(c b2)
expect "force-push blocked" 1 "$b2" refs/heads/feat/a "$a2"
expect "push to main blocked" 1 "$a1" refs/heads/main "$Z"
expect "renovate branch blocked" 1 "$a1" refs/heads/renovate/foo "$Z"
expect "dependabot branch blocked" 1 "$a1" refs/heads/dependabot/npm/foo "$Z"
expect "deletion allowed" 0 "$Z" refs/heads/feat/a "$a2"
git checkout -q main; c m2 --author="Teammate <t@example.com>" >/dev/null; git push -q origin main; git checkout -q feat/a
expect "behind base blocked" 1 "$a2" refs/heads/feat/a "$a1"
git merge -q --no-edit origin/main; m=$(git rev-parse HEAD)
expect "after merging base allowed (base authors ignored)" 0 "$m" refs/heads/feat/a "$a2"
o=$(c other --author="Bot <bot@example.com>")
expect "other author blocked" 1 "$o" refs/heads/feat/a "$m"

expect "HEAD:main blocked" 1 "$a1" refs/heads/main "$Z" HEAD
expect "deleting main blocked" 1 "$Z" refs/heads/main "$a1" "(delete)"
git checkout -q -b feat/c origin/main
git merge -q --no-ff --no-edit "$o" 2>/dev/null; fm=$(git rev-parse HEAD)
expect "earlier foreign commit blocked" 1 "$(c c1)" refs/heads/feat/c "$fm"

exit "$fails"
