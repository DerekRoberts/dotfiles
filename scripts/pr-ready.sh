#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # ok/bad always succeed; GraphQL vars are literal
# pr-ready — re-read a PR live from GitHub and say whether it is ready for review.
# Usage: pr-ready [<number>|<url>] [-R owner/repo]   (defaults to the current branch's PR)
# Exit 0 only when every check passes; prints one line per check and the check time.
set -euo pipefail
unset GITHUB_TOKEN GH_TOKEN

MIN_QUIET_MINUTES="${PR_READY_MIN_QUIET_MINUTES:-10}"

command -v gh >/dev/null || { echo "pr-ready: gh not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "pr-ready: jq not found" >&2; exit 2; }

pr=$(gh pr view "$@" --json number,url,isDraft,state,body,mergeable,mergeStateStatus,headRefOid,baseRefName,headRefName,statusCheckRollup,commits) \
    || { echo "pr-ready: could not read the PR" >&2; exit 2; }

url=$(jq -r ".url // empty" <<<"$pr")
[[ -n "$url" ]] || { echo "pr-ready: gh returned no PR data" >&2; exit 2; }
num=$(jq -r .number <<<"$pr")
repo=$(sed -E 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#' <<<"$url")
owner=${repo%/*}; name=${repo#*/}
head=$(jq -r .headRefOid <<<"$pr")
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

echo "$url (checked $(date '+%Y-%m-%d %H:%M %Z'))"

[[ $(jq -r .state <<<"$pr") == OPEN ]] && ok "open" || bad "not open"
[[ $(jq -r '.body // ""' <<<"$pr") == "ON HOLD:"* ]] && bad "description starts with ON HOLD:" || ok "not on hold"

# Checks: every check finished and passed.
pending=$(jq '[.statusCheckRollup[] | select((.status // "COMPLETED") != "COMPLETED" or (.state // "") == "PENDING" or (.state // "") == "EXPECTED")] | length' <<<"$pr")
failed=$(jq -r '[.statusCheckRollup[] | select((.conclusion // .state) as $c | $c != null and ($c | IN("SUCCESS","NEUTRAL","SKIPPED","COMPLETED","PENDING","EXPECTED","")) | not) | (.name // .context)] | join(", ")' <<<"$pr")
total=$(jq '.statusCheckRollup | length' <<<"$pr")
if (( pending > 0 )); then bad "checks: $pending still running"
elif [[ -n "$failed" ]]; then bad "checks failed: $failed"
else ok "checks: $total done and green"; fi

# Unresolved review threads.
threads=$(gh api graphql --paginate -f owner="$owner" -f name="$name" -F num="$num" -f query='
  query($owner:String!,$name:String!,$num:Int!,$endCursor:String){repository(owner:$owner,name:$name){pullRequest(number:$num){
    reviewThreads(first:100,after:$endCursor){nodes{isResolved} pageInfo{hasNextPage endCursor}}}}}' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)] | length' | awk '{n+=$1} END{print n+0}')
(( threads == 0 )) && ok "0 unresolved threads" || bad "$threads unresolved review thread(s)"

# Behind base.
behind=$(gh api "repos/$repo/compare/$(jq -r .baseRefName <<<"$pr")...$head" --jq .behind_by)
(( behind == 0 )) && ok "0 commits behind $(jq -r .baseRefName <<<"$pr")" || bad "$behind commit(s) behind $(jq -r .baseRefName <<<"$pr")"

# Mergeable and blocked only by review.
mergeable=$(jq -r .mergeable <<<"$pr"); mss=$(jq -r .mergeStateStatus <<<"$pr")
case "$mergeable/$mss" in
    MERGEABLE/BLOCKED|MERGEABLE/CLEAN|MERGEABLE/HAS_HOOKS|MERGEABLE/DRAFT) ok "mergeable ($mss)" ;;
    *) bad "not mergeable: mergeable=$mergeable mergeStateStatus=$mss" ;;
esac

# Quiet period since the last push (earliest check suite on the head commit ~ push time).
pushed=$(gh api "repos/$repo/commits/$head/check-suites" --jq '[.check_suites[].created_at] | min // empty')
if [[ -z "$pushed" ]]; then
    bad "push time unknown (no check suites on the head commit yet)"
else
    age=$(( ($(date +%s) - $(date -d "$pushed" +%s)) / 60 ))
    (( age >= MIN_QUIET_MINUTES )) && ok "last push ${age} min ago" || bad "last push ${age} min ago (need ${MIN_QUIET_MINUTES})"
fi

# The head must not have moved while checking.
now_head=$(gh pr view "$url" --json headRefOid --jq .headRefOid)
[[ "$now_head" == "$head" ]] || bad "new push during the check; run again"

if (( fail )); then echo "NOT READY"; exit 1; fi
jq -e .isDraft <<<"$pr" >/dev/null && echo "READY (still a draft: gh pr ready $num -R $repo)" || echo "READY"
