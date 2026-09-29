#!/usr/bin/env bash
# test-bcgov-push.sh — bcgov-push checks and commit building, as examples.
# Usage: bash scripts/test-bcgov-push.sh
set -euo pipefail

# shellcheck source=scripts/bcgov-push.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bcgov-push.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0

# expect <name> <pass|fail> <command...>
expect() {
    local name="$1" want="$2" got=pass; shift 2
    ( "$@" ) >/dev/null 2>&1 || got=fail
    if [[ "$got" == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (wanted $want)"; fails=1; fi
}

expect "branch: type/name"            pass check_branch_name fix/codeowners
expect "branch: no type"              fail check_branch_name codeowners
expect "branch: tool prefix"          fail check_branch_name cursor/codeowners-1a2b
expect "branch: tool word"            fail check_branch_name chore/claude-cleanup
expect "branch: tool-like substring"  pass check_branch_name fix/cursorless-paging
expect "branch: every tool word"      fail check_branch_name fix/chatgpt-output
expect "title: conventional"          pass check_title "fix(codeowners): drop departed owners"
expect "title: breaking"              pass check_title "feat!: new preset"
expect "title: not conventional"      fail check_title "Update CODEOWNERS"
expect "title: attribution"           fail check_title "fix: thing (Cursor Agent)"
expect "text: plain"                  pass check_text_clean t <<< $'Removes two owners.\n\nCloses #12'
expect "text: AI trailer"             fail check_text_clean t <<< 'Co-authored-by: Cursor Agent <cursoragent@cursor.com>'
expect "text: generated line"         fail check_text_clean t <<< 'Generated with Claude Code'
expect "text: tool trailer"           fail check_text_clean t <<< 'Co-authored-by: Gemini <gemini@example.com>'
expect "text: human trailer"          pass check_text_clean t <<< 'Co-authored-by: Jane Doe <jane@example.com>'

# A fork branch with an AI-authored commit becomes one commit by the local user.
git init -q -b main "$TMP/repo"; cd "$TMP/repo"
git config user.name "Test User"; git config user.email "test@example.com"; git config commit.gpgsign false
printf 'a\nb\n' > CODEOWNERS; git add CODEOWNERS; git commit -q -m "chore: init"
base="$(git rev-parse HEAD)"
git checkout -q -b fork
printf 'a\n' > CODEOWNERS
GIT_AUTHOR_NAME="Cursor Agent" GIT_AUTHOR_EMAIL="cursoragent@cursor.com" \
    git commit -q -a -m $'chore: drop b\n\nCo-authored-by: Cursor Agent <cursoragent@cursor.com>'
fork="$(git rev-parse HEAD)"

expect "diff: clean deletion only"    pass check_diff_clean "$base" "$fork"
commit="$(GIT_AUTHOR_NAME=Leaked make_commit "$fork" "$base" "chore(codeowners): drop b")"
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: '$2' != '$3'"; fails=1; fi; }
check "commit: tree matches fork"     "$(git rev-parse "$commit^{tree}")" "$(git rev-parse "$fork^{tree}")"
check "commit: parent is base"        "$(git rev-parse "$commit^")" "$base"
check "commit: local author"          "$(git log -1 --format='%an <%ae>|%cn <%ce>' "$commit")" "Test User <test@example.com>|Test User <test@example.com>"
check "commit: message is title only" "$(git log -1 --format=%B "$commit")" "chore(codeowners): drop b"

# Updates: the upstream branch must only carry trees published from the fork.
git branch -q target "$commit"
expect "update: target came from fork" pass check_target_from_fork "$base" target fork
git checkout -q target; echo c >> CODEOWNERS; git commit -q -a -m "fix: direct edit"
expect "update: direct upstream edit" fail check_target_from_fork "$base" target fork
git checkout -q fork

mkdir .cursor; echo x > .cursor/rules; git add .cursor
git commit -q -m "chore: add rules"
expect "diff: tool-specific file"     fail check_diff_clean "$base" HEAD
git rm -q -r .cursor; echo "Generated with Cursor" > NOTES; git add NOTES
git commit -q -m "docs: notes"
expect "diff: attribution text"       fail check_diff_clean "$base" HEAD

exit "$fails"
