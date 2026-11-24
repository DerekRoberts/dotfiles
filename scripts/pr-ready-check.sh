#!/usr/bin/env bash
# pr-ready-check.sh — mechanically verify whether a pull request meets the Core Ready rule:
#   1. PR state is OPEN and mergeable is MERGEABLE.
#   2. Head is not behind PR base ref (0 commits on base not in head).
#   3. CI checks have 0 pending and 0 failing (CANCELLED/TIMED_OUT/FAILURE count as fail).
#   4. Unresolved reviewThreads == 0 (including outdated threads).
#
# After a push, --watch waits for this PR's checks (fail-fast) with a 30-minute
# cap. The script does the waiting so the caller is not burning AI credits.
# Exit 0 if Ready, 1 if not Ready or a check failed, 2 on usage error, 3 if the
# cap was hit (stuck, not failed): leave the PR not-Ready for a later pass.
#
# Usage:
#   pr-ready-check.sh [PR_NUMBER] [--repo OWNER/REPO] [--watch] [--timeout SECONDS]
set -euo pipefail

pr=""
repo=""
watch=0
timeout=1800

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
        -h|--help)
            echo "Usage: $0 [PR_NUMBER] [--repo OWNER/REPO] [--watch] [--timeout SECONDS]"
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

fetch_checks() {
    # Bound the request by a remaining-seconds budget when one is passed, so a
    # slow GitHub call cannot run past the watch cap unnoticed.
    local budget="${1:-}"
    local out=""
    if [[ -n "$budget" ]] && command -v timeout >/dev/null 2>&1; then
        if [[ "$budget" -lt 1 ]]; then
            return 124
        fi
        out="$(timeout "${budget}s" gh pr checks "$pr" --repo "$repo" --json name,state,bucket 2>/dev/null)" || return $?
        echo "$out"
    else
        gh pr checks "$pr" --repo "$repo" --json name,state,bucket 2>/dev/null || echo "[]"
    fi
}

# Core Ready: CANCELLED/TIMED_OUT/FAILURE count as fail. gh puts cancellations
# in the `cancel` bucket, not `fail`.
list_failures() {
    echo "$1" | jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "    - " + (if .bucket == "cancel" then "CANCELLED: " else "FAILED: " end) + .name'
}

# Wait for this PR's checks until they all finish, any one fails (including
# CANCELLED), or the cap is hit. Prints progress; returns 0 (done, no
# failures), 1 (failed), 3 (stuck).
wait_for_ci() {
    local start_time current_time elapsed remaining sleep_for checks_json pending_count failing_count check_count fetch_status
    start_time="$(date +%s)"

    while true; do
        current_time="$(date +%s)"
        elapsed=$((current_time - start_time))
        remaining=$((timeout - elapsed))
        if [[ "$remaining" -le 0 ]]; then
            echo "STUCK: CI checks on $repo #$pr still pending or unreported after ${timeout}s. Leave not-Ready for a later pass (CI failure check or a re-check)." >&2
            return 3
        fi

        fetch_status=0
        checks_json="$(fetch_checks "$remaining")" || fetch_status=$?
        current_time="$(date +%s)"
        elapsed=$((current_time - start_time))
        remaining=$((timeout - elapsed))

        if [[ "$fetch_status" -ne 0 ]]; then
            if [[ "$remaining" -le 0 || "$fetch_status" -eq 124 ]]; then
                echo "STUCK: CI checks on $repo #$pr still pending or unreported after ${timeout}s. Leave not-Ready for a later pass (CI failure check or a re-check)." >&2
                return 3
            fi
            checks_json="[]"
        fi

        check_count="$(echo "$checks_json" | jq 'length')"
        pending_count="$(echo "$checks_json" | jq '[.[] | select(.bucket == "pending")] | length')"
        failing_count="$(echo "$checks_json" | jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length')"

        # Conclusive failure is reported even if the fetch landed just past the cap.
        if [[ "$failing_count" -gt 0 ]]; then
            echo "FAILED: $failing_count CI check(s) failed on $repo #$pr."
            list_failures "$checks_json"
            return 1
        fi

        if [[ "$check_count" -gt 0 && "$pending_count" -eq 0 ]]; then
            # Conclusive completion, even if the fetch landed just past the cap.
            echo "CI checks finished on $repo #$pr (${elapsed}s; 0 pending, 0 failing)."
            return 0
        fi

        if [[ "$remaining" -le 0 ]]; then
            echo "STUCK: CI checks on $repo #$pr still pending or unreported after ${timeout}s. Leave not-Ready for a later pass (CI failure check or a re-check)." >&2
            return 3
        fi

        if [[ "$check_count" -eq 0 ]]; then
            echo "Waiting for CI checks to appear on $repo #$pr (${elapsed}s / ${timeout}s)..."
        else
            echo "Waiting for $pending_count pending CI check(s) on $repo #$pr (${elapsed}s / ${timeout}s)..."
        fi
        # Sleep up to 10s, but not past the cap, so a short --timeout is honored.
        sleep_for=10
        if [[ "$remaining" -lt "$sleep_for" ]]; then
            sleep_for="$remaining"
        fi
        sleep "$sleep_for"
    done
}

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

    local state mergeable base_ref head_ref status_state
    state="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.state // empty')"
    mergeable="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.mergeable // empty')"
    base_ref="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.baseRefName // empty')"
    head_ref="$(echo "$pr_data" | jq -r '.data.repository.pullRequest.headRefName // empty')"
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
    local checks_json pending_count failing_count
    checks_json="$(fetch_checks)"
    pending_count="$(echo "$checks_json" | jq '[.[] | select(.bucket == "pending")] | length')"
    failing_count="$(echo "$checks_json" | jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length')"

    if [[ "$pending_count" -eq 0 && "$failing_count" -eq 0 && "$status_state" == "SUCCESS" ]]; then
        echo "  ✓ CI Checks: SUCCESS (0 pending, 0 failing)"
    else
        echo "  ✗ CI Checks: $status_state ($pending_count pending, $failing_count failing)"
        if [[ "$failing_count" -gt 0 ]]; then
            list_failures "$checks_json"
        fi
        if [[ "$pending_count" -gt 0 ]]; then
            echo "$checks_json" | jq -r '.[] | select(.bucket == "pending") | "    - PENDING: " + .name'
        fi
        failed=1
    fi

    if [[ "$failed" -eq 0 ]]; then
        echo "==> PR #$pr is READY for review."
        return 0
    else
        echo "==> PR #$pr is NOT ready."
        return 1
    fi
}

if [[ "$watch" -eq 1 ]]; then
    ci_status=0
    wait_for_ci || ci_status=$?
    if [[ "$ci_status" -ne 0 ]]; then
        exit "$ci_status"
    fi
fi

check_pr
