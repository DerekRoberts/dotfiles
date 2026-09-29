#!/usr/bin/env bash
# test-agent-guard.sh — check config/agent-guard allow/deny decisions.
# Usage: bash scripts/test-agent-guard.sh
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$DOTFILES_DIR/config/agent-guard/agent-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

result() {
    local want="$1" got="$2" what="$3"
    if [[ "$got" == "$want" ]]; then echo "ok   $want: $what"; else echo "FAIL want $want got $got: $what"; fails=1; fi
}
verdict() { if "$@" 2>/dev/null; then echo allow; else echo deny; fi; }
check()     { result "$1" "$(verdict sh "$GUARD" shell "$2" "${3:-$TMP}")" "$2"; }
check_mcp() { result "$1" "$(verdict sh "$GUARD" mcp "$2" "$3")" "mcp $2"; }

# Everyday agent work stays allowed.
check allow 'git status && git diff'
check allow 'git push -u origin feat/x'
check allow 'unset GITHUB_TOKEN && gh pr create --title "t" --body "b"'
check allow 'gh pr view 12 --json state'
check allow 'gh pr edit 12 --body "no merge here"'
check allow 'gh api repos/o/r/pulls/12/comments --paginate'
check allow 'gh api -X PATCH repos/o/r/pulls/12 -f body=text'
check allow 'gh api repos/o/r/git/refs -f ref=refs/heads/x -f sha=abc'
check allow 'git commit -m "docs: explain why gh pr merge is blocked"'
check allow 'git tag -l "v*"'
check allow 'gh pr view -R bcgov/action-crunchy 5'

# Issue transfers are allowed everywhere, crunchy included.
check allow 'gh issue transfer 7 bcgov/nr-fom'
check allow 'gh issue transfer 7 bcgov/action-crunchy'
check allow 'gh issue transfer 7 bcgov/nr-fom -R bcgov/action-crunchy'
check allow "gh api graphql -f query='mutation { transferIssue(input:{issueId:\"I_1\",repositoryId:\"R_1\"}) { issue { url } } }'"
check_mcp allow transfer_issue '{"owner":"bcgov","repo":"action-crunchy","new_repo":"nr-fom"}'

# Merges.
check deny 'gh pr merge 12 --squash'
check deny 'unset GITHUB_TOKEN && gh pr merge --auto 12'
check deny 'gh api -X PUT repos/o/r/pulls/12/merge'
check deny "gh api graphql -f query='mutation { mergePullRequest(input:{pullRequestId:\"x\"}) { clientMutationId } }'"

# Force pushes and tags.
check deny 'git push --force origin feat/x'
check deny 'git push --force-with-lease'
check deny 'git push -f'
check deny 'git push origin +feat/x'
check deny 'git push --tags'
check deny 'git tag v1.2.3'
check deny 'git tag -a v1 -m release'
check deny 'gh release create v1'

# Comments, reviews, closes.
check deny 'gh pr comment 12 --body hi'
check deny 'gh issue comment 3 -b hi'
check deny 'gh pr review 12 --approve'
check deny 'gh pr close 12'
check deny 'gh api repos/o/r/issues/12/comments -f body=hi'
check deny 'gh api -X PATCH repos/o/r/issues/3 -f state=closed'

# Repository and org settings.
check deny 'gh repo edit --visibility public'
check deny 'gh secret set TOKEN'
check deny 'gh api -X PUT repos/o/r/branches/main/protection --input p.json'
check deny 'gh api -X POST repos/o/r/rulesets --input r.json'
check deny 'gh api -X PUT repos/o/r/collaborators/someone'
check deny 'gh api -X PATCH repos/o/r -f default_branch=dev'
check deny 'gh api --method PATCH orgs/bcgov -f x=y'

# Other crunchy writes stay blocked.
check deny 'gh pr create -R bcgov/action-crunchy --title t --body b'
check deny 'gh api -X PUT repos/bcgov/actions-openshift/contents/crunchy/values.yaml -f message=m'
git init -q "$TMP/crunchy" && git -C "$TMP/crunchy" remote add origin https://github.com/bcgov/action-crunchy.git
check deny 'git commit -m change' "$TMP/crunchy"
check deny 'git push' "$TMP/crunchy"
check allow 'git status' "$TMP/crunchy"
git init -q "$TMP/aos" && git -C "$TMP/aos" remote add origin git@github.com:bcgov/actions-openshift.git
mkdir -p "$TMP/aos/crunchy" "$TMP/aos/other"
echo a > "$TMP/aos/crunchy/f" && echo b > "$TMP/aos/other/f"
git -C "$TMP/aos" add other/f
check allow 'git commit -m other' "$TMP/aos"
git -C "$TMP/aos" add crunchy/f
check deny 'git commit -m crunchy' "$TMP/aos"

# GitHub MCP tools.
check_mcp deny merge_pull_request '{"owner":"o","repo":"r","pullNumber":1}'
check_mcp deny add_issue_comment '{"body":"hi"}'
check_mcp deny update_pull_request '{"state":"closed"}'
check_mcp deny create_or_update_file '{"owner":"bcgov","repo":"action-crunchy"}'
check_mcp allow create_pull_request '{"owner":"o","repo":"r"}'
check_mcp allow list_pull_request_reviews '{}'

# Cursor adapter.
mkdir -p "$TMP/bin" && install -m 755 "$GUARD" "$TMP/bin/agent-guard"
cursor() {
    jq -cn --arg c "$1" '{hook_event_name: "beforeShellExecution", command: $c, cwd: "/tmp"}' \
        | PATH="$TMP/bin:$PATH" sh "$DOTFILES_DIR/config/agent-guard/cursor-hook.sh" | jq -r .permission
}
result allow "$(cursor 'gh pr view 1')" "cursor gh pr view"
result deny "$(cursor 'gh pr merge 1')" "cursor gh pr merge"

exit "$fails"
