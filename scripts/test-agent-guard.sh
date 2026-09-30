#!/usr/bin/env bash
# test-agent-guard.sh — the agent-guard rules, as examples.
# Usage: bash scripts/test-agent-guard.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/agent-guard"
fails=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

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
deny  'git update-ref refs/tags/v1 HEAD'
allow 'git update-ref refs/heads/x HEAD'
REPO="$TMP/repo"
git init -q "$REPO" && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
git -C "$REPO" tag v1.2.3
deny  'git push origin v1.2.3' "$REPO"
deny  'git push origin +v1.2.3:v1.2.3' "$REPO"
deny  'git push origin refs/tags/v9'
allow 'git push origin main' "$REPO"
allow 'git push -u origin feat/x' "$REPO"

# Comments, reviews, closes
deny  'gh pr comment 12 --body hi'
deny  'gh pr review 12 --approve'
deny  'gh pr close 12'
deny  'gh issue comment 3 --body hi'
deny  'gh issue close 3'
deny  'gh issue delete 3'
allow 'gh issue create --title t --body b'
allow "gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: \"PRRT_x\"}) { thread { isResolved } } }'"
allow "gh api graphql -f query='mutation { dismissPullRequestReview(input: {pullRequestReviewId: \"PRR_x\", message: \"Not applicable.\"}) { pullRequestReview { state } } }'"
deny  "gh api graphql -f query='mutation { submitPullRequestReview(input: {pullRequestReviewId: \"PRR_x\", event: APPROVE}) { pullRequestReview { state } } }'"

# Raw gh api writes: -X, --method, or -f/-F with no -X (implies POST)
deny  'gh api repos/o/r/issues/3/comments -f body=hi'
deny  'gh api repos/o/r/issues/3/comments -fbody=hi'
deny  'gh api repos/o/r/pulls/12/reviews --raw-field=event=APPROVE'
deny  'gh api repos/o/r/issues/3/comments --input=payload.json'
deny  'gh api repos/o/r/issues/3 -fstate=closed'
deny  'gh api --method=PATCH repos/o/r/pulls/12 --field=state=closed'
deny  'gh api -X POST repos/o/r/issues/3/comments -f body=hi'
deny  'gh api --method POST repos/o/r/pulls/12/comments -f body=hi'
deny  'gh api repos/o/r/pulls/12/comments/99/replies -F body=hi'
deny  'gh api -X PATCH repos/o/r/issues/comments/99 -f body=hi'
deny  'gh api -XDELETE repos/o/r/issues/comments/99'
deny  'gh api repos/o/r/pulls/12/reviews -f event=APPROVE'
deny  'gh api -X PATCH repos/o/r/issues/3 -f state=closed'
deny  'gh api --method=PATCH repos/o/r/pulls/12 -f state=closed'
deny  'gh api repos/o/r/pulls/12 -X PATCH -F state=open'
deny  'gh api -X PUT repos/o/r/actions/secrets/TOKEN -f encrypted_value=x -f key_id=1'
deny  'gh api -X DELETE repos/o/r/actions/secrets/TOKEN'
deny  'gh api repos/o/r/actions/variables -f name=N -f value=v'
deny  'gh api -X PATCH repos/o/r/actions/variables/N -f value=v'
deny  'gh api -X PUT repos/o/r/environments/prod/secrets/TOKEN -f encrypted_value=x'
deny  'gh api -X DELETE repos/o/r/environments/prod/variables/N'
deny  'gh api repos/o/r/branches/main/protection -X PUT --input p.json'
deny  'gh api repos/o/r/pulls/12/merge -X PUT'
allow 'gh api -X PATCH repos/o/r/pulls/12 -f title=t -f body=b'
allow 'gh api repos/o/r/pulls/12 -f body="see the /comments endpoint"'
allow 'gh api repos/o/r/pulls/12/comments --paginate'
allow 'gh api -X GET repos/o/r/issues/3/comments -f per_page=100'
allow 'gh api repos/o/r/actions/secrets'
allow 'gh api repos/o/r/environments/prod/variables'
allow 'gh api -X POST repos/o/r/issues -f title=t -f body=b'
allow 'gh api -X POST repos/o/r/pulls/12/requested_reviewers -f "reviewers[]=u"'

# GraphQL mutations
deny  "gh api graphql -f query='mutation { addComment(input: {subjectId: \"I_x\", body: \"hi\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { addPullRequestReview(input: {pullRequestId: \"PR_x\", event: APPROVE}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: \"PRRT_x\", body: \"hi\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { closeIssue(input: {issueId: \"I_x\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { closePullRequest(input: {pullRequestId: \"PR_x\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { reopenIssue(input: {issueId: \"I_x\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { updatePullRequest(input: {pullRequestId: \"PR_x\", state: CLOSED}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { updatePullRequest(input: {pullRequestId: \"PR_x\", state : CLOSED}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { updateIssue(input: {id: \"I_x\", state : CLOSED}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"PR_x\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"PR_x\"}) { clientMutationId } }'"
deny  "gh api graphql -f query='mutation { unresolveReviewThread(input: {threadId: \"PRRT_x\"}) { thread { isResolved } } }'"
allow "gh api graphql -f query='mutation { updatePullRequest(input: {pullRequestId: \"PR_x\", title: \"t\"}) { pullRequest { state } } }'"
allow "gh api graphql -f query='query { repository(owner: \"o\", name: \"r\") { pullRequest(number: 1) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { body } } } } } } }'"

# Repo settings, secrets, variables
deny  'gh repo edit --visibility public'
deny  'gh repo archive o/r'
deny  'gh repo delete o/r'
deny  'gh secret set TOKEN'
deny  'gh variable delete NAME'
deny  'gh api -X PUT repos/o/r/branches/main/protection'
allow 'gh api repos/o/r/branches/main/protection'
allow 'gh repo view o/r'

# Crunchy: contributions and issue transfers allowed (cberg-aot reviews, see instructions.md)
allow 'gh pr create -R bcgov/action-crunchy --title t --body b'
allow 'git push' "$HOME/Repos/action-crunchy"
allow 'cd ~/Repos/action-crunchy && git commit -m x'
allow 'git commit -m x -- crunchy/file' "$HOME/Repos/actions-openshift"
deny  'gh pr merge 12 -R bcgov/action-crunchy'
allow 'gh issue transfer 7 bcgov/nr-fom'
allow 'gh issue transfer 7 bcgov/action-crunchy'

# GitHub MCP tools
expect deny  mcp merge_pull_request '{}'
expect deny  mcp add_issue_comment '{}'
expect deny  mcp add_comment_to_pending_review '{}'
expect deny  mcp create_pull_request_review '{}'
expect allow mcp list_pull_request_reviews '{}'
expect allow mcp resolve_review_thread '{"threadId":"PRRT_x"}'
expect deny  mcp unresolve_review_thread '{"threadId":"PRRT_x"}'
expect allow mcp create_pull_request '{"repo":"r"}'
expect deny  mcp update_issue '{"issue_number":3,"state":"closed"}'
expect deny  mcp update_pull_request '{"pullNumber":12,"state":"closed"}'
expect allow mcp update_pull_request '{"pullNumber":12,"title":"t","body":"b"}'
expect allow mcp list_issues '{"state":"open"}'
expect allow mcp create_or_update_file '{"repo":"action-crunchy"}'
expect allow mcp transfer_issue '{"repo":"action-crunchy"}'

# Cursor adapter
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
