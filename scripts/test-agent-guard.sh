#!/usr/bin/env bash
# test-agent-guard.sh — the agent-guard rules, as examples.
# Usage: bash scripts/test-agent-guard.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/agent-guard"
fails=0

expect() {
    local want="$1" got="deny"; shift
    if sh "$DIR/agent-guard.sh" "$@" 2>/dev/null; then got="allow"; fi
    if [[ "$got" == "$want" ]]; then echo "ok   $want: ${*:2}"; else echo "FAIL want $want: ${*:2}"; fails=1; fi
}
allow() { expect allow shell "$@"; }
deny()  { expect deny shell "$@"; }

# Everyday work
allow 'gh pr create --title "t" --body "b"'
allow 'gh pr edit 12 --body "b"'
allow 'gh pr view 12'
allow 'git push -u origin feat/x'
allow 'git commit -m "docs: explain why gh pr merge is blocked"'

# Merging
deny  'gh pr merge 12 --squash'
deny  'unset GITHUB_TOKEN && gh pr merge 12'
deny  'gh api -X PUT repos/o/r/pulls/12/merge'
allow 'gh api repos/o/r/pulls/12/merge'

# Force-push and tags
deny  'git push --force origin feat/x'
deny  'git push -f'
deny  'git push --force-with-lease'
deny  'git push --tags'
deny  'git tag v1.2.3'
allow 'git tag -l'

# Comments, reviews, closes
deny  'gh pr comment 12 --body hi'
deny  'gh pr review 12 --approve'
deny  'gh pr close 12'
deny  'gh issue comment 3 --body hi'
deny  'gh issue close 3'
deny  'gh issue delete 3'
allow 'gh issue create --title t --body b'

# Repo settings, secrets, variables
deny  'gh repo edit --visibility public'
deny  'gh repo archive o/r'
deny  'gh repo delete o/r'
deny  'gh secret set TOKEN'
deny  'gh variable delete NAME'
deny  'gh api -X PUT repos/o/r/branches/main/protection'
allow 'gh api repos/o/r/branches/main/protection'
allow 'gh repo view o/r'

# Crunchy: writes blocked, reads and issue transfers allowed
deny  'gh pr create -R bcgov/action-crunchy --title t --body b'
deny  'git push' "$HOME/Repos/action-crunchy"
allow 'git status' "$HOME/Repos/action-crunchy"
allow 'gh issue transfer 7 bcgov/nr-fom'
allow 'gh issue transfer 7 bcgov/action-crunchy'

# GitHub MCP tools
expect deny  mcp merge_pull_request '{}'
expect deny  mcp add_issue_comment '{}'
expect allow mcp list_pull_request_reviews '{}'
expect allow mcp create_pull_request '{"repo":"r"}'
expect deny  mcp create_or_update_file '{"repo":"action-crunchy"}'
expect allow mcp transfer_issue '{"repo":"action-crunchy"}'

# Cursor adapter
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
install -m 755 "$DIR/agent-guard.sh" "$TMP/agent-guard"
cursor() {
    jq -cn --arg c "$1" '{hook_event_name: "beforeShellExecution", command: $c, cwd: "/tmp"}' \
        | PATH="$TMP:$PATH" sh "$DIR/cursor-hook.sh" | jq -r .permission
}
if [[ "$(cursor 'gh pr view 1')" == allow && "$(cursor 'gh pr merge 1')" == deny ]]; then
    echo "ok   cursor adapter"
else
    echo "FAIL cursor adapter"; fails=1
fi

exit "$fails"
