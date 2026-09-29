#!/usr/bin/env bash
# test-agent-guard.sh — feed sample hook payloads to config/cursor/hooks/agent-guard.sh
# and check allow/deny. Usage: scripts/test-agent-guard.sh
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$DOTFILES_DIR/config/cursor/hooks/agent-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

decide() {
    sh "$GUARD" | jq -r .permission
}

check() {
    local want="$1" cmd="$2" cwd="${3:-$TMP}" got
    got="$(jq -cn --arg c "$cmd" --arg d "$cwd" \
        '{hook_event_name: "beforeShellExecution", command: $c, cwd: $d}' | decide)"
    if [[ "$got" == "$want" ]]; then echo "ok   $want: $cmd"; else echo "FAIL want $want got $got: $cmd"; fails=1; fi
}

check_mcp() {
    local want="$1" tool="$2" args="$3" got
    got="$(jq -cn --arg t "$tool" --arg a "$args" \
        '{hook_event_name: "beforeMCPExecution", mcp_server_name: "github", tool_name: $t, tool_input: $a}' | decide)"
    if [[ "$got" == "$want" ]]; then echo "ok   $want: mcp $tool"; else echo "FAIL want $want got $got: mcp $tool"; fails=1; fi
}

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

# Merges.
check deny 'gh pr merge 12 --squash'
check deny 'unset GITHUB_TOKEN && gh pr merge --auto 12'
check deny 'gh api -X PUT repos/o/r/pulls/12/merge'
check deny "gh api graphql -f query='mutation { mergePullRequest(input:{pullRequestId:\"x\"}) { clientMutationId } }'"
check deny "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input:{}) { clientMutationId } }'"

# Force pushes and tags.
check deny 'git push --force origin feat/x'
check deny 'git push --force-with-lease'
check deny 'git push -f'
check deny 'git -C repo push -uf origin x'
check deny 'git push origin +feat/x'
check deny 'git push --tags'
check deny 'git push origin v1.2.3 refs/tags/v1.2.3'
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
check deny 'gh repo archive o/r'
check deny 'gh secret set TOKEN'
check deny 'gh api -X PUT repos/o/r/branches/main/protection --input p.json'
check deny 'gh api -X POST repos/o/r/rulesets --input r.json'
check deny 'gh api -X PUT repos/o/r/environments/prod'
check deny 'gh api -X PUT repos/o/r/collaborators/someone'
check deny 'gh api -X DELETE repos/o/r/hooks/1'
check deny 'gh api -X PATCH repos/o/r -f default_branch=dev'
check deny 'gh api --method PATCH orgs/bcgov -f x=y'

# Crunchy.
check deny 'gh pr create -R bcgov/action-crunchy --title t --body b'
check deny 'gh api -X PUT repos/bcgov/actions-openshift/contents/crunchy/values.yaml -f message=m'
git init -q "$TMP/crunchy" && git -C "$TMP/crunchy" remote add origin https://github.com/bcgov/action-crunchy.git
check deny 'git commit -m change' "$TMP/crunchy"
check deny "cd $TMP/crunchy && git push"
check allow 'git status' "$TMP/crunchy"
git init -q "$TMP/aos" && git -C "$TMP/aos" remote add origin git@github.com:bcgov/actions-openshift.git
mkdir -p "$TMP/aos/crunchy" "$TMP/aos/other"
echo a > "$TMP/aos/crunchy/f" && echo b > "$TMP/aos/other/f"
git -C "$TMP/aos" add other/f
check allow 'git commit -m other' "$TMP/aos"
git -C "$TMP/aos" add crunchy/f
check deny 'git commit -m crunchy' "$TMP/aos"

# MCP (GitHub server).
check_mcp deny merge_pull_request '{"owner":"o","repo":"r","pullNumber":1}'
check_mcp deny add_issue_comment '{"body":"hi"}'
check_mcp deny update_pull_request '{"state":"closed"}'
check_mcp deny create_or_update_file '{"owner":"bcgov","repo":"action-crunchy"}'
check_mcp allow create_pull_request '{"owner":"o","repo":"r"}'
check_mcp allow list_pull_request_reviews '{}'

exit "$fails"
