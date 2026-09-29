#!/usr/bin/env bash
# bcgov-push — publish a branch that was prepared in a personal fork to the
# upstream org repository as the local git user.
#
# The fork branch is never replayed. The script writes ONE new commit whose
# tree equals the fork branch tip, authored and committed by the local git
# identity, with a message built from --title only. Fork commit authors,
# messages, and trailers never reach upstream. Updates to an existing upstream
# branch are appended as another commit (fast-forward, never a force-push);
# the upstream branch must only carry changes that came from the fork branch.
#
# Usage:
#   bcgov-push <fork-owner/repo> <fork-branch> --to <type>/<name> [options]
#
# Options:
#   --to <type>/<name>   Upstream branch to create or update (required)
#   --title <text>       Conventional Commits title for the commit and a new PR
#                        (default: subject of the fork branch tip)
#   --body-file <file>   PR body; required when no open PR exists for --to
#   --draft              Open the new PR as a draft
#   --dry-run            Build and check the commit; push nothing, open nothing
#   -h, --help           Show this help
#
# Environment:
#   REPOS_DIR            Local checkouts (default: ~/Repos). The checkout named
#                        after the repository must have origin = the upstream.
#   BCGOV_PUSH_ORGS      Space-separated upstream orgs allowed
#                        (default: "bcgov bcgov-c")

set -euo pipefail

REF_NS="refs/bcgov-push"

die()  { echo "bcgov-push: $*" >&2; exit 1; }
info() { echo "  → $*"; }

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }

# Branch names on upstream must be <type>/<name> and must not name an AI tool.
check_branch_name() {
    local name="$1"
    [[ "$name" =~ ^[a-z]+/[A-Za-z0-9._/-]+$ ]] \
        || die "--to '$name' must look like <type>/<name>, e.g. fix/codeowners"
    if [[ "${name,,}" =~ (^|[/._-])(cursor|claude|copilot|codex|grok|devin|anthropic|openai|gemini)([/._-]|$) ]]; then
        die "--to '$name' names an AI tool; pick a neutral branch name"
    fi
}

check_title() {
    local title="$1"
    [[ "$title" =~ ^[a-z]+(\([^\)]+\))?!?:\ .+ ]] \
        || die "title '$title' is not a Conventional Commits subject (type(scope): summary)"
    check_text_clean "title" <<< "$title"
}

# Reads text on stdin; fails when it carries AI attribution.
check_text_clean() {
    local what="$1" hits
    hits="$(grep -n -i -E \
        -e 'cursoragent@cursor[.]com' \
        -e 'noreply@anthropic[.]com' \
        -e 'co-authored-by:.*(cursor|claude|copilot|anthropic|openai|codex|grok)' \
        -e 'generated (with|by) .*(cursor|claude|copilot|chatgpt|codex|grok)' \
        -e 'cursor[.]com' \
        -e 'cursor agent' || true)"
    [[ -z "$hits" ]] || die "$what carries AI attribution:"$'\n'"$hits"
}

# Fails when <from>..<to> adds tool-specific files or attribution text.
check_diff_clean() {
    local from="$1" to="$2" paths
    paths="$(git diff --name-only --diff-filter=AMR "$from" "$to" \
        | grep -E '(^|/)(\.cursor(/|$)|\.cursorrules$|\.cursorignore$|\.cursorindexingignore$)' || true)"
    [[ -z "$paths" ]] || die "change adds tool-specific files:"$'\n'"$paths"
    git diff --no-color --no-ext-diff -U0 "$from" "$to" \
        | awk '/^\+\+\+ /{next} /^\+/{print}' | check_text_clean "change"
}

# Fails unless <target>'s tree equals a commit on <base>..<fork>, i.e. every
# change on the upstream branch came from the fork branch. A commit made
# directly on the upstream branch would be dropped by the next publish.
check_target_from_fork() {
    local base="$1" target="$2" fork="$3" trees
    trees="$(git log --format=%T "$base..$fork")"
    grep -qxF "$(git rev-parse "$target^{tree}")" <<< "$trees" \
        || die "upstream branch has changes that are not on the fork branch; put them on the fork branch first"
}

# Prints a new commit: tree of <tree_ref>, parent <parent>, local identity.
make_commit() {
    local tree_ref="$1" parent="$2" title="$3"
    env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_AUTHOR_DATE \
        -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u GIT_COMMITTER_DATE \
        git commit-tree "${tree_ref}^{tree}" -p "$parent" -m "$title"
}

main() {
    local fork="" fork_branch="" to="" title="" body_file="" draft=0 dry_run=0
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to)        [[ $# -ge 2 ]] || die "--to needs a value"; to="$2"; shift 2 ;;
            --title)     [[ $# -ge 2 ]] || die "--title needs a value"; title="$2"; shift 2 ;;
            --body-file) [[ $# -ge 2 ]] || die "--body-file needs a value"; body_file="$2"; shift 2 ;;
            --draft)     draft=1; shift ;;
            --dry-run)   dry_run=1; shift ;;
            -h|--help)   usage; exit 0 ;;
            -*)          die "unknown option: $1" ;;
            *)           positional+=("$1"); shift ;;
        esac
    done
    [[ ${#positional[@]} -eq 2 ]] || { usage >&2; exit 1; }
    fork="${positional[0]}"; fork_branch="${positional[1]}"
    [[ "$fork" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "fork must be OWNER/REPO, got '$fork'"
    [[ -n "$to" ]] || die "--to <type>/<name> is required"
    check_branch_name "$to"
    [[ -z "$body_file" || -f "$body_file" ]] || die "--body-file '$body_file' not found"
    [[ -z "$body_file" ]] || check_text_clean "PR body" < "$body_file"
    command -v git >/dev/null || die "git not found"
    command -v gh >/dev/null || die "gh not found"
    unset GITHUB_TOKEN

    local upstream org repo default_branch
    upstream="$(gh api "repos/$fork" --jq '.parent.full_name // empty')"
    [[ -n "$upstream" ]] || die "$fork is not a fork"
    org="${upstream%%/*}"; repo="${upstream#*/}"
    [[ " ${BCGOV_PUSH_ORGS:-bcgov bcgov-c} " == *" $org "* ]] \
        || die "upstream $upstream is outside BCGOV_PUSH_ORGS"
    default_branch="$(gh api "repos/$upstream" --jq .default_branch)"
    [[ "$to" != "$default_branch" ]] || die "--to must not be the default branch"

    local checkout origin_url
    checkout="${REPOS_DIR:-$HOME/Repos}/$repo"
    [[ -d "$checkout/.git" || -f "$checkout/.git" ]] || die "no checkout at $checkout (clone it first)"
    cd "$checkout"
    origin_url="$(git remote get-url origin)"
    [[ "${origin_url,,}" =~ github\.com[:/]${upstream,,}(\.git)?$ ]] \
        || die "$checkout origin is $origin_url, not $upstream"

    local name email
    name="$(git config user.name || true)"; email="$(git config user.email || true)"
    [[ -n "$name" && -n "$email" ]] || die "git user.name and user.email must be set"
    check_text_clean "git identity" <<< "$name <$email>"

    trap 'git for-each-ref --format="delete %(refname)" "$REF_NS/" | git update-ref --stdin' EXIT
    local fork_url="https://github.com/$fork.git"
    [[ "$origin_url" == git@* ]] && fork_url="git@github.com:$fork.git"
    info "Fetching $upstream $default_branch and $fork $fork_branch"
    git fetch -q --no-tags origin "+refs/heads/$default_branch:$REF_NS/base"
    git fetch -q --no-tags "$fork_url" "+refs/heads/$fork_branch:$REF_NS/fork"

    local base parent from
    base="$(git merge-base "$REF_NS/base" "$REF_NS/fork")" \
        || die "fork branch shares no history with $upstream $default_branch"
    [[ "$(git rev-parse "$REF_NS/fork^{tree}")" != "$(git rev-parse "$base^{tree}")" ]] \
        || die "fork branch has no changes against $default_branch"

    if git ls-remote --exit-code -q origin "refs/heads/$to" >/dev/null; then
        git fetch -q --no-tags origin "+refs/heads/$to:$REF_NS/target"
        [[ "$(git merge-base "$REF_NS/base" "$REF_NS/target")" == "$base" ]] \
            || die "$to and the fork branch sit on different $default_branch commits; rebase one of them first"
        check_target_from_fork "$base" "$REF_NS/target" "$REF_NS/fork"
        if [[ "$(git rev-parse "$REF_NS/target^{tree}")" == "$(git rev-parse "$REF_NS/fork^{tree}")" ]]; then
            info "$upstream $to already matches $fork $fork_branch; nothing to push"
            parent=""
        else
            parent="$(git rev-parse "$REF_NS/target")"
        fi
        from="$REF_NS/target"
    else
        parent="$base"
        from="$base"
    fi

    local pr_url=""
    pr_url="$(gh pr list -R "$upstream" --head "$to" --state open --json url --jq '.[0].url // empty')"
    [[ -n "$pr_url" || -n "$body_file" ]] || die "no open PR for $to; --body-file is required to open one"

    if [[ -n "$parent" ]]; then
        [[ -n "$title" ]] || title="$(git log -1 --format=%s "$REF_NS/fork")"
        check_title "$title"
        check_diff_clean "$from" "$REF_NS/fork"

        local commit
        commit="$(make_commit "$REF_NS/fork" "$parent" "$title")"
        echo ""
        git --no-pager log -1 --format='  commit %H%n  author %an <%ae>%n  %s' "$commit"
        git --no-pager diff --stat "$from" "$commit" | sed 's/^/  /'
        if [[ $dry_run -eq 1 ]]; then
            info "Dry run: not pushing $to to $upstream"
            exit 0
        fi
        info "Pushing $to to $upstream"
        git push origin "$commit:refs/heads/$to"
    elif [[ $dry_run -eq 1 ]]; then
        exit 0
    fi

    if [[ -n "$pr_url" ]]; then
        info "PR already open: $pr_url"
        return 0
    fi
    [[ -n "$title" ]] || title="$(git log -1 --format=%s "$REF_NS/fork")"
    check_title "$title"
    local pr_args=(-R "$upstream" --base "$default_branch" --head "$to"
        --title "$title" --body-file "$body_file" --assignee @me)
    [[ $draft -eq 0 ]] || pr_args+=(--draft)
    gh pr create "${pr_args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
