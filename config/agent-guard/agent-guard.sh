#!/bin/sh
# agent-guard — tool-neutral check of an AI agent action against the Hard Stops
# in config/instructions.md. Installed to ~/.local/bin/agent-guard.
#
#   agent-guard shell "<command>" [cwd]
#   agent-guard mcp "<tool_name>" "<args json>"
#
# Exit 0 = allow. Exit 2 = deny, reason on stderr. Any AI tool with a
# pre-command hook can call this; see config/agent-guard/cursor-hook.sh.
#
# This guides a helpful agent that forgot a rule mid-task. It is not a sandbox
# and does not try to catch deliberate bypasses (bash -c, scripts, curl).

deny() {
    echo "Blocked by agent-guard: $1. A human does this; draft it in chat instead." >&2
    exit 2
}
has() { printf '%s\n' "$1" | grep -Eq -- "$2"; }

CRUNCHY='action-crunchy|actions-openshift.*crunchy/'

# ── MCP tools (GitHub) ───────────────────────────────────────────────────────
if [ "$1" = mcp ]; then
    tool="$2" args="$3"
    has "$tool" 'transfer_issue' && exit 0
    has "$tool" '^(add|create|submit|reply|update|delete|remove|set|merge|push|close|archive)_' || exit 0
    has "$tool" 'merge|comment|review|secret|variable|protection|ruleset|collaborator|hook|repository|tag|release' \
        && deny "GitHub tool $tool"
    has "$args" '"state"[[:space:]]*:[[:space:]]*"closed"' && deny "closing a PR or issue"
    has "$args" "$CRUNCHY" && deny "write touching crunchy"
    exit 0
fi

[ "$1" = shell ] || { echo "usage: agent-guard shell <command> [cwd] | mcp <tool> <args>" >&2; exit 64; }
cmd="$2" dir="${3:-$PWD}"

# GraphQL mutations (queries often span lines, so check the whole command).
if has "$cmd" 'gh[[:space:]].*api[[:space:]].*graphql'; then
    has "$cmd" 'mergePullRequest|enablePullRequestAutoMerge|mergeBranch' && deny "merge"
    has "$cmd" 'addComment|addPullRequestReview|submitPullRequestReview|addDiscussionComment' && deny "comment or review"
    has "$cmd" 'closePullRequest|closeIssue' && deny "closing a PR or issue"
    has "$cmd" 'updateRepository|archiveRepository|BranchProtectionRule|RepositoryRuleset' && deny "repository settings change"
fi

# Judge each simple command on its own so a commit message that mentions
# "gh pr merge" is not mistaken for one.
START='^[[:space:](]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
GH="${START}gh[[:space:]]+"
GIT="${START}git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+"

printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g' | {
while IFS= read -r seg; do
    if has "$seg" "$GH"; then
        has "$seg" "${GH}issue[[:space:]]+transfer([[:space:]]|$)" && continue
        has "$seg" "${GH}pr[[:space:]]+(merge|comment|review|close)([[:space:]]|$)" && deny "gh pr merge/comment/review/close"
        has "$seg" "${GH}issue[[:space:]]+(comment|close|delete)([[:space:]]|$)" && deny "gh issue comment/close/delete"
        has "$seg" "${GH}release[[:space:]]+(create|delete|edit|upload)([[:space:]]|$)" && deny "releases and tags"
        has "$seg" "${GH}repo[[:space:]]+(edit|archive|unarchive|delete|rename|deploy-key)([[:space:]]|$)" && deny "repository settings change"
        has "$seg" "${GH}(secret|variable)[[:space:]]+(set|delete|remove)([[:space:]]|$)" && deny "secret or variable change"

        if has "$seg" "${GH}api([[:space:]]|$)"; then
            # gh api is a write with -X/--method other than GET, or with fields.
            if has "$seg" '(-X|--method)[[:space:]=]*(POST|PUT|PATCH|DELETE)' \
                || { has "$seg" '[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$)' && ! has "$seg" '(-X|--method)[[:space:]=]*GET'; }; then
                has "$seg" 'graphql' && continue
                has "$seg" '/pulls/[0-9]+/merge|/merges' && deny "merge"
                has "$seg" '/comments|/reviews' && deny "comment or review"
                has "$seg" 'state=closed' && deny "closing a PR or issue"
                has "$seg" '/git/tags|/releases|refs/tags/' && deny "releases and tags"
                has "$seg" '/protection|/rulesets|/environments|/secrets|/variables|/collaborators|/hooks|/keys|/actions/permissions|orgs/' \
                    && deny "repository or org settings change"
                has "$seg" "repos/[^/[:space:]]+/[^/[:space:]'\"]+/?(['\"[:space:]]|$)" && deny "repository settings change"
                has "$seg" "$CRUNCHY" && deny "write touching crunchy"
            fi
        elif ! has "$seg" "${GH}[a-z-]+[[:space:]]+(view|list|diff|checks|status|clone|download|watch)([[:space:]]|$)"; then
            has "$seg" "$CRUNCHY" && deny "write touching crunchy"
        fi
    fi

    if has "$seg" "$GIT"; then
        if has "$seg" "${GIT}push([[:space:]]|$)"; then
            has "$seg" '[[:space:]](-[A-Za-z]*f[A-Za-z]*|--force[a-z-]*(=[^[:space:]]*)?|--mirror)([[:space:]]|$)|[[:space:]]\+[^[:space:]]' \
                && deny "force push"
            has "$seg" '[[:space:]](--tags|--follow-tags)([[:space:]]|$)|refs/tags/' && deny "pushing tags"
        fi
        # Creating tags counts: push.followTags would carry them on the next push.
        has "$seg" "${GIT}tag[[:space:]]+([^-[:space:]]|-[asfdmF]([[:space:]]|$)|--(annotate|sign|force|delete))" && deny "creating or deleting tags"

        if has "$seg" "${GIT}(commit|push)([[:space:]]|$)"; then
            origin="$(git -C "$dir" remote get-url origin 2>/dev/null)"
            has "$origin" 'action-crunchy' && deny "git write in bcgov/action-crunchy"
            has "$origin" 'actions-openshift' && has "$seg" "${GIT}commit" \
                && has "$(git -C "$dir" diff --cached --name-only 2>/dev/null)" '^crunchy/' \
                && deny "commit touching crunchy/ in bcgov/actions-openshift"
        fi
    fi
done
exit 0
}
