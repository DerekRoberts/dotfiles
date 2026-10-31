#!/usr/bin/env bash
# test-commit-msg.sh — the commit-msg hook, as examples.
# Usage: bash scripts/test-commit-msg.sh
set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/hooks/commit-msg"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0

# expect <name> <message in> <message out>
expect() {
    printf '%s\n' "$2" > "$TMP/msg"
    sh "$HOOK" "$TMP/msg"
    if [[ "$(cat "$TMP/msg")" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; cat "$TMP/msg"; fails=1; fi
}

expect "plain message unchanged" \
    $'fix: thing\n\nWhy it changed.' \
    $'fix: thing\n\nWhy it changed.'
expect "AI trailer stripped" \
    $'fix: thing\n\nCo-authored-by: Cursor Agent <cursoragent@cursor.com>' \
    $'fix: thing'
expect "AI trailer stripped, any case" \
    $'fix: thing\n\nBody.\n\nCo-Authored-By: Claude <noreply@anthropic.com>' \
    $'fix: thing\n\nBody.'
expect "human trailer kept" \
    $'fix: thing\n\nCo-authored-by: Jane Doe <jane@example.com>\nCo-authored-by: Cursor Agent <cursoragent@cursor.com>' \
    $'fix: thing\n\nCo-authored-by: Jane Doe <jane@example.com>'

# reject <name> <message>: hook must exit non-zero
reject() {
    printf '%s\n' "$2" > "$TMP/msg"
    if sh "$HOOK" "$TMP/msg" 2>/dev/null; then echo "FAIL $1 (accepted)"; fails=1; else echo "ok   $1"; fi
}
expect "non-conventional subject allowed" $'Update stuff' $'Update stuff'
expect "short subject like Trigger" $'Trigger' $'Trigger'
reject "Generated with line" $'fix: thing\n\nGenerated with SomeTool'
reject "indented Generated with line" $'fix: thing\n\n  Generated with SomeTool'
reject "Generated with line in merge" $'Merge branch \'main\'\n\nGenerated with SomeTool'
expect "breaking change with scope" $'feat(api)!: drop v1' $'feat(api)!: drop v1'
expect "merge subject allowed" $'Merge branch \'main\' into feat/x' $'Merge branch \'main\' into feat/x'

exit "$fails"
