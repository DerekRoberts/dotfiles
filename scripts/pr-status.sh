#!/usr/bin/env bash
# shellcheck disable=SC2016  # GraphQL vars are literal
# pr-status — read-only list of PRs and default-branch runs that need Derek, one line per item.
# Usage: pr-status [--yes] [days]   (failed runs from the last N days, default 2)
#   Every run lists failed runs whose log shows the runner was blocked from the OpenShift API,
#   then asks "N blocked runs found, rerun them? [y/N]" (default No) and reruns exactly those
#   (failed jobs, attempt 1 only; never PROD runs or runs still running or waiting on approval).
#   --yes      rerun without asking. With no terminal it only reports.
set -euo pipefail
unset GITHUB_TOKEN GH_TOKEN

ME=DerekRoberts
YES=false
[[ "${1:-}" == --yes ]] && { YES=true; shift; }
DAYS="${1:-2}"
# Runner IP blocked from the OpenShift API (oc login / kubectl to api.*:6443), seen in
# actions-openshift 38076084540, nr-fds-pyetl 38767262795, pubcode 37707107595.
IP_BLOCK='dial tcp [0-9.]+:6443: i/o timeout'
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

tmp=$(mktemp); trap 'rm -f "$tmp" "$tmp.runs" "$tmp.blocked"' EXIT
prs=$( { search review "review-requested:$ME" && search direct "user-review-requested:$ME" &&
    search assigned "assignee:$ME" && search authored "author:$ME"; } | jq -s '
  group_by(.url) | map(.[0] + {tags: map(.tag)})')

jq -r --argjson support "$support" '
  .[]
  | (.projectItems.nodes | map(select(.project.number == 16 and .project.owner.login == "bcgov"))) as $p
  | ($p[0].fieldValueByName.name // null) as $status
  | (.repository.nameWithOwner) as $repo
  | (.tags | index("review") != null) as $rev
  | (.tags | index("direct") != null) as $direct
  | (.tags | index("assigned") != null) as $asg
  | (.tags | index("authored") != null) as $own
  | (.commits.nodes[0].commit.statusCheckRollup.state // "NONE") as $ci
  | select(.repository.isArchived | not)
  | select($repo != "MinionTech/metacurious")
  | select($status != "Done")
  | select($direct or (($support | index($repo)) == null))
  | select($rev or $asg or ($p | length > 0) or ($repo | startswith("DerekRoberts/")))
  | if ($own or $asg) and ($ci == "FAILURE" or $ci == "ERROR") then "2\tfailing checks\t\(.url)"
    elif ($own or $asg) and .reviewDecision == "CHANGES_REQUESTED" then "2\tchanges requested\t\(.url)"
    elif $rev then "1\treview requested\t\(.url)"
    elif .isDraft then empty
    elif $own and (.reviewDecision == "APPROVED" or .mergeStateStatus == "CLEAN") and ($ci != "PENDING") then "1\tready to merge\t\(.url)"
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
        branch=$(gh api "repos/$repo" --jq 'if .archived then "" else .default_branch end') ||
            { echo "WARN could not read $repo"; exit 0; }
        [[ -n "$branch" ]] || exit 0
        # Latest run per workflow; report it only if that latest run failed or timed out.
        gh run list -R "$repo" -b "$branch" --created ">=$since" -L 1000 \
            --json workflowDatabaseId,workflowName,conclusion,url,createdAt |
            jq -r 'group_by(.workflowDatabaseId)[] | max_by(.createdAt)
                   | select(.conclusion | IN("failure","timed_out")) | "\(.workflowName): \(.url)"' ||
            echo "WARN could not list runs for $repo"
    ) &
done | sort | tee "$tmp.runs"

check_blocked() { # $1 = run URL; prints "ok|skip <tab> url <tab> reason" for IP-blocked runs
    local url=$1 repo id run why=""
    repo=$(sed -E 's#https://github.com/([^/]+/[^/]+)/actions/runs/.*#\1#' <<<"$url")
    id=$(sed -E 's#.*/runs/([0-9]+).*#\1#' <<<"$url")
    gh run view "$id" -R "$repo" --log-failed 2>/dev/null | grep -Eq "$IP_BLOCK" || return 0
    run=$(gh run view "$id" -R "$repo" --json attempt,status,headSha,jobs)
    if (( $(jq .attempt <<<"$run") >= 2 )); then why="already rerun (attempt $(jq .attempt <<<"$run"))"
    elif [[ $(jq -r .status <<<"$run") != completed ]]; then why="not finished or waiting on approval"
    elif jq -e '.jobs[].name | test("\\bprod(uction)?\\b"; "i")' <<<"$run" >/dev/null; then why="has a PROD job"
    elif gh api "repos/$repo/deployments?sha=$(jq -r .headSha <<<"$run")" --jq '.[].environment' |
        grep -Eqi '\bprod(uction)?\b'; then why="deploys to PROD"
    fi
    if [[ -n "$why" ]]; then printf 'skip\t%s\t%s\n' "$url" "$why"; else printf 'ok\t%s\t\n' "$url"; fi
}

echo "== IP-blocked runs"
{
    grep -Eo 'https://github.com/[^ ]+/actions/runs/[0-9]+' "$tmp.runs" || true
    awk -F'\t' '$2=="failing checks" {print $3}' "$tmp" | while read -r pr; do
        gh pr checks "$pr" --json state,link --jq '.[] | select(.state=="FAILURE") | .link' || true
    done | grep -Eo 'https://github.com/[^ ]+/actions/runs/[0-9]+' || true
} | sort -u | while read -r url; do check_blocked "$url"; done >"$tmp.blocked"
awk -F'\t' '$1=="skip" {printf "skip   %s (%s)\n", $2, $3}' "$tmp.blocked"
awk -F'\t' '$1=="ok" {printf "found  %s\n", $2}' "$tmp.blocked"
n=$(awk -F'\t' '$1=="ok"' "$tmp.blocked" | wc -l)
if (( n > 0 )); then
    answer=n
    if $YES; then answer=y
    elif [[ -t 0 && -t 1 ]]; then read -r -p "$n blocked runs found, rerun them? [y/N] " answer
    else echo "$n blocked runs found. No terminal, so not rerunning (use --yes)."; fi
    if [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]]; then
        awk -F'\t' '$1=="ok" {print $2}' "$tmp.blocked" | while read -r url; do
            repo=$(sed -E 's#https://github.com/([^/]+/[^/]+)/actions/runs/.*#\1#' <<<"$url")
            gh run rerun "${url##*/}" -R "$repo" --failed && echo "rerun  $url"
        done
    elif [[ -t 0 && -t 1 ]]; then echo "Not rerun."; fi
fi
echo "(checked $(date '+%Y-%m-%d %H:%M %Z'))"
