#!/usr/bin/env bash
# shellcheck disable=SC2016  # GraphQL vars are literal
# pr-status — read-only list of PRs and default-branch runs that need Derek, one line per item.
# Usage: pr-status [days]   (failed runs from the last N days, default 2)
set -euo pipefail
unset GITHUB_TOKEN GH_TOKEN

ME=DerekRoberts
DAYS="${1:-2}"
command -v gh >/dev/null || { echo "pr-status: gh not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "pr-status: jq not found" >&2; exit 2; }

# Roles from brain repo-rules.md: "| `owner/repo` | 1 Develop | ..."
rules=$(gh api repos/$ME/brain/contents/repo-rules.md -H 'Accept: application/vnd.github.raw')
roles=$(awk -F'|' '$2 ~ /`[^`]+\/[^`]+`/ {gsub(/[` ]/,"",$2); r=$3; gsub(/^ +| +$/,"",r); print $2 "\t" r}' <<<"$rules")
support=$(awk -F'\t' '$2 ~ /^3/ {print $1}' <<<"$roles" | jq -R . | jq -sc .)
watch=$(awk -F'\t' '$2 ~ /^[12] / {print $1}' <<<"$roles")

search() { # $1 = tag, $2 = search qualifiers
    gh api graphql --paginate -f q="is:pr is:open archived:false $2" -f query='
      query($q:String!,$endCursor:String){search(query:$q,type:ISSUE,first:50,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{... on PullRequest{url isDraft reviewDecision mergeStateStatus
          repository{nameWithOwner isArchived}
          commits(last:1){nodes{commit{statusCheckRollup{state}}}}
          projectItems(first:20){nodes{project{number owner{... on Organization{login}}}
            fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}}' \
      --jq ".data.search.nodes[] | . + {tag:\"$1\"}"
}

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
prs=$( { search review "review-requested:$ME"; search assigned "assignee:$ME"; search authored "author:$ME"; } | jq -s '
  group_by(.url) | map(.[0] + {tags: map(.tag)})')

jq -r --argjson support "$support" '
  .[]
  | (.projectItems.nodes | map(select(.project.number == 16 and .project.owner.login == "bcgov"))) as $p
  | ($p[0].fieldValueByName.name // null) as $status
  | (.repository.nameWithOwner) as $repo
  | (.tags | index("review") != null) as $rev
  | (.tags | index("assigned") != null) as $asg
  | (.commits.nodes[0].commit.statusCheckRollup.state // "NONE") as $ci
  | select(.repository.isArchived | not)
  | select($repo != "MinionTech/metacurious")
  | select($status != "Done")
  | select($rev or (($support | index($repo)) == null))
  | select($rev or $asg or ($p | length > 0) or ($repo | startswith("DerekRoberts/")))
  | if ($ci == "FAILURE" or $ci == "ERROR") then "2\tfailing checks\t\(.url)"
    elif .reviewDecision == "CHANGES_REQUESTED" then "2\tchanges requested\t\(.url)"
    elif $rev then "1\treview requested\t\(.url)"
    elif .isDraft then empty
    elif (.reviewDecision == "APPROVED" or .mergeStateStatus == "CLEAN") and ($ci != "PENDING") then "1\tready to merge\t\(.url)"
    elif $asg then "1\tassigned\t\(.url)"
    else empty end' <<<"$prs" | sort -u >"$tmp"

echo "== Waiting on your review or merge"
awk -F'\t' '$1==1 {printf "%-17s %s\n", $2, $3}' "$tmp"
echo "== Failing or changes requested"
awk -F'\t' '$1==2 {printf "%-17s %s\n", $2, $3}' "$tmp"

echo "== Failed runs on the default branch (last $DAYS days)"
since=$(date -u -d "-$DAYS days" +%Y-%m-%d)
for repo in $watch; do
    (
        info=$(gh api "repos/$repo" --jq 'select(.archived|not) | .default_branch' 2>/dev/null) || exit 0
        [[ -n "$info" ]] || exit 0
        # Latest run per workflow; report it only if that latest run failed.
        gh run list -R "$repo" -b "$info" --created ">=$since" -L 100 \
            --json workflowName,conclusion,url,createdAt 2>/dev/null |
            jq -r 'group_by(.workflowName)[] | max_by(.createdAt)
                   | select(.conclusion == "failure") | "\(.workflowName): \(.url)"'
    ) &
done | sort
wait
echo "(checked $(date '+%Y-%m-%d %H:%M %Z'))"
