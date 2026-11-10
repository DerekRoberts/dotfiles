#!/usr/bin/env bash
# pr-ready-check.sh — mechanically verify whether a pull request meets the Core Ready rule:
#   1. PR state is OPEN and mergeable is MERGEABLE.
#   2. Head is not behind PR base ref (0 commits on base not in head).
#   3. CI checks have 0 pending and 0 failing (CANCELLED/TIMED_OUT/FAILURE count as fail).
#   4. Unresolved reviewThreads == 0 (including outdated threads).
#   5. ≥10 minutes elapsed since last push.
#
# Usage:
#   pr-ready-check.sh [PR_NUMBER] [--repo OWNER/REPO] [--watch] [--timeout SECONDS] [--no-time-check]
set -euo pipefail

pr=""
repo=""
watch=0
timeout=900
check_time=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            repo="$2"
            shift 2
            ;;
        --watch)
            watch=1
            shift
            ;;
        --timeout)
            timeout="$2"
            shift 2
            ;;
        --no-time-check)
            check_time=0
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [PR_NUMBER] [--repo OWNER/REPO] [--watch] [--timeout SECONDS] [--no-time-check]"
            exit 0
            ;;
        *)
            if [[ -z "$pr" && "$1" =~ ^[0-9]+$ ]]; then
                pr="$1"
                shift
            else
                echo "Unknown argument: $1" >&2
                exit 2
            fi
            ;;
    esac
done

# Resolve repo and PR number if not provided
if [[ -z "$repo" ]]; then
    repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    if [[ -z "$repo" ]]; then
        echo "Error: Could not determine GitHub repository. Specify with --repo OWNER/REPO." >&2
        exit 2
    fi
fi

if [[ -z "$pr" ]]; then
    pr="$(gh pr view --json number -q .number 2>/dev/null || true)"
    if [[ -z "$pr" ]]; then
        echo "Error: Could not determine PR number for current branch. Specify PR_NUMBER." >&2
        exit 2
    fi
fi

owner="${repo%%/*}"
name="${repo#*/}"

check_pr() {
    # shellcheck disable=SC2016
    local query='
query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      state
      mergeable
      baseRefName
      headRefName
      headRefOid
      commits(last: 1) {
        nodes {
          commit {
            committedDate
            statusCheckRollup {
              state
            }
          }
        }
      }
      reviewThreads(first: 100) {
        totalCount
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              path
              line
              author { login }
            }
          }
        }
      }
    }
  }
}'

    local pr_data
    pr_data="$(gh api graphql -f query="$query" -F owner="$owner" -F name="$name" -F pr="$pr")"

    local state mergeable base_ref head_ref committed_date status_state
    state="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.state // empty')"
    mergeable="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.mergeable // empty')"
    base_ref="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.baseRefName // empty')"
    head_ref="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.headRefName // empty')"
    committed_date="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.commits.nodes[0].commit.committedDate // empty')"
    status_state="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.state // empty')"

    if [[ -z "$state" ]]; then
        echo "FAIL: Could not query PR #$pr in $repo"
        return 1
    fi

    local failed=0
    echo "=== Ready Check: $repo #$pr ==="

    # 1. PR State
    if [[ "$state" == "OPEN" ]]; then
        echo "  ✓ State: OPEN"
    else
        echo "  ✗ State: $state (must be OPEN)"
        failed=1
    fi

    # 2. Mergeability
    if [[ "$mergeable" == "MERGEABLE" ]]; then
        echo "  ✓ Mergeable: MERGEABLE"
    else
        echo "  ✗ Mergeable: $mergeable (must be MERGEABLE)"
        failed=1
    fi

    # 3. Behind base check
    local behind_by
    behind_by="$(gh api "repos/$owner/$name/compare/$base_ref...$head_ref" --jq '.behind_by' 2>/dev/null || echo "unknown")"
    if [[ "$behind_by" == "0" ]]; then
        echo "  ✓ Base ref alignment: 0 commits behind $base_ref"
    else
        echo "  ✗ Base ref alignment: $behind_by commits behind $base_ref (must be 0; merge $base_ref)"
        failed=1
    fi

    # 4. Review threads
    local unresolved_threads
    unresolved_threads="$(echo "$pr_data" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)]')"
    local unresolved_count
    unresolved_count="$(echo "$unresolved_threads" | jq 'length')"
    if [[ "$unresolved_count" -eq 0 ]]; then
        echo "  ✓ Review threads: 0 unresolved"
    else
        echo "  ✗ Review threads: $unresolved_count unresolved threads block Ready"
        echo "$unresolved_threads" | jq -r '.[] | "    - Thread " + .id + " by @" + (.comments.nodes[0].author.login // "unknown") + " on " + (.comments.nodes[0].path // "file") + ":" + ((.comments.nodes[0].line // 0)|tostring)'
        failed=1
    fi

    # 5. CI Status checks
    # Inspect individual checks for pending or failing
    local checks_json
    checks_json="$(gh pr checks "$pr" --repo "$repo" --json name,state,bucket,event 2>/dev/null || echo "[]")"
    local pending_count failing_count
    pending_count="$(echo "$checks_json" | jq '[.[] | select(.bucket == "pending")] | length')"
    failing_count="$(echo "$checks_json" | jq '[.[] | select(.bucket == "fail")] | length')"

    if [[ "$pending_count" -eq 0 && "$failing_count" -eq 0 && "$status_state" == "SUCCESS" ]]; then
        echo "  ✓ CI Checks: SUCCESS (0 pending, 0 failing)"
    else
        echo "  ✗ CI Checks: $status_state ($pending_count pending, $failing_count failing)"
        if [[ "$failing_count" -gt 0 ]]; then
            echo "$checks_json" | jq -r '.[] | select(.bucket == "fail") | "    - FAILED: " + .name'
        fi
        if [[ "$pending_count" -gt 0 ]]; then
            echo "$checks_json" | jq -r '.[] | select(.bucket == "pending") | "    - PENDING: " + .name'
        fi
        failed=1
    fi

    # 6. Elapsed time check (>= 10 min since last push)
    if [[ -n "$committed_date" ]]; then
        local commit_epoch now_epoch elapsed_sec elapsed_min
        commit_epoch="$(date -d "$committed_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$committed_date" +%s 2>/dev/null || echo 0)"
        now_epoch="$(date +%s)"
        elapsed_sec=$((now_epoch - commit_epoch))
        elapsed_min=$((elapsed_sec / 60))

        if [[ "$elapsed_sec" -ge 600 ]]; then
            echo "  ✓ Elapsed time: ${elapsed_min}m since last commit (≥10 min requirement met)"
        else
            if [[ "$check_time" -eq 1 ]]; then
                echo "  ✗ Elapsed time: ${elapsed_min}m since last commit (<10 min; wait $(( (600 - elapsed_sec) / 60 + 1 ))m for automated bots)"
                failed=1
            else
                echo "  ⚠ Elapsed time: ${elapsed_min}m since last commit (skipped via --no-time-check)"
            fi
        fi
    fi

    if [[ "$failed" -eq 0 ]]; then
        echo "==> PR #$pr is READY for review."
        return 0
    else
        echo "==> PR #$pr is NOT ready."
        return 1
    fi
}

start_time="$(date +%s)"
while true; do
    if check_pr; then
        exit 0
    fi

    if [[ "$watch" -eq 0 ]]; then
        exit 1
    fi

    current_time="$(date +%s)"
    elapsed=$((current_time - start_time))
    if [[ "$elapsed" -ge "$timeout" ]]; then
        echo "Timed out after ${timeout}s watching PR #$pr in $repo." >&2
        exit 1
    fi

    echo "Re-checking in 15 seconds (elapsed: ${elapsed}s / ${timeout}s)..."
    sleep 15
done
