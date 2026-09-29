#!/bin/sh
# agent-guard.sh — Cursor agent hook (beforeShellExecution, beforeMCPExecution).
# Denies the Hard Stops in config/instructions.md for agents only; Derek's own
# terminal never runs this. Installed to ~/.cursor/hooks/ by scripts/setup/ai.sh.
#
# Safety belt, not a sandbox: commands hidden in `bash -c`, scripts, or
# variables are not parsed. Reads hook JSON on stdin, writes a decision on stdout.

export PATH="${HOME}/.local/bin:${PATH}"

deny() {
    jq -cn --arg m "Blocked by dotfiles agent-guard: $1. A human does this; draft it in chat instead." \
        '{permission: "deny", user_message: $m, agent_message: $m}'
    exit 0
}
allow() { printf '%s\n' '{"permission":"allow"}'; exit 0; }

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"permission":"deny","user_message":"agent-guard: jq not found on PATH","agent_message":"agent-guard: jq not found on PATH"}'
    exit 0
fi

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"

has() { printf '%s\n' "$1" | grep -Eq -- "$2"; }

CRUNCHY='bcgov/action-crunchy|action-crunchy'
OPENSHIFT_CRUNCHY='actions-openshift.*crunchy/'

# ── MCP tools (GitHub servers only) ──────────────────────────────────────────
if [ "$event" = "beforeMCPExecution" ]; then
    server="$(printf '%s' "$input" | jq -r '[.mcp_server_name, .url, .command] | map(. // "") | join(" ")')"
    has "$server" '[Gg]it[Hh]ub' || allow
    tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
    args="$(printf '%s' "$input" | jq -r '.tool_input // empty')"
    has "$tool" '^(add|create|submit|reply|update|delete|remove|set|merge|mark|push|close|archive|transfer|enable|disable|dismiss|lock)_' || allow
    has "$tool" 'merge|comment|review|secret|variable|protection|ruleset|collaborator|hook|repository|tag|release' \
        && deny "GitHub MCP tool $tool"
    has "$args" '"state"[[:space:]]*:[[:space:]]*"closed"' && deny "closing a PR or issue ($tool)"
    has "$args" "$CRUNCHY|$OPENSHIFT_CRUNCHY" && deny "write touching crunchy ($tool)"
    allow
fi

[ "$event" = "beforeShellExecution" ] || allow

cmd="$(printf '%s' "$input" | jq -r '.command // empty')"
dir="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$dir" ] || dir="$PWD"

# GraphQL mutations: match anywhere, queries often span lines.
if has "$cmd" 'gh[[:space:]].*api[[:space:]].*graphql' || has "$cmd" 'graphql.*gh[[:space:]]'; then
    has "$cmd" 'mergePullRequest|enablePullRequestAutoMerge|mergeBranch' && deny "GraphQL merge mutation"
    has "$cmd" 'addComment|addPullRequestReview|submitPullRequestReview|addDiscussionComment' && deny "GraphQL comment/review mutation"
    has "$cmd" 'closePullRequest|closeIssue' && deny "GraphQL close mutation"
    has "$cmd" 'updateRepository|archiveRepository|BranchProtectionRule|RepositoryRuleset|updateEnvironment|deleteEnvironment' && deny "GraphQL settings mutation"
    has "$cmd" 'createRef' && has "$cmd" 'refs/tags/' && deny "GraphQL tag creation"
    has "$cmd" "$CRUNCHY|$OPENSHIFT_CRUNCHY" && has "$cmd" 'mutation' && deny "GraphQL write touching crunchy"
fi

# Leading noise before the program name: subshell/brace openers, env
# assignments, and wrapper words.
PFX='^[[:space:](!{]*((env|command|exec|sudo|time|nohup)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:]]*/)?'
GITCMD="${PFX}git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+"
GH="${PFX}gh[[:space:]]+"

origin_of() { git -C "$1" remote get-url origin 2>/dev/null; }

# Split on ; && || | and newlines; judge each simple command on its own.
segs="$(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')"
newline='
'
set -f
IFS_OLD="$IFS"; IFS="$newline"
for seg in $segs; do
    IFS="$IFS_OLD"

    # Track `cd` so git checks see the right checkout.
    if has "$seg" '^[[:space:]]*cd[[:space:]]+[^[:space:]]+'; then
        target="$(printf '%s\n' "$seg" | sed -E 's/^[[:space:]]*cd[[:space:]]+([^[:space:]]+).*/\1/; s/^["'\'']//; s/["'\'']$//')"
        case "$target" in
            "~"*) target="${HOME}${target#\~}" ;;
            /*) ;;
            *) target="$dir/$target" ;;
        esac
        dir="$target"
        IFS="$newline"; continue
    fi

    # ── gh ───────────────────────────────────────────────────────────────────
    if has "$seg" "$GH"; then
        has "$seg" "${GH}pr[[:space:]]+(merge|comment|review|close)([[:space:]]|$)" && deny "gh pr merge/comment/review/close"
        has "$seg" "${GH}issue[[:space:]]+(comment|close|delete)([[:space:]]|$)" && deny "gh issue comment/close/delete"
        has "$seg" "${GH}release[[:space:]]+(create|delete|edit|upload)([[:space:]]|$)" && deny "gh release (creates tags)"
        has "$seg" "${GH}repo[[:space:]]+(edit|archive|unarchive|delete|rename|deploy-key)([[:space:]]|$)" && deny "repository settings change"
        has "$seg" "${GH}(secret|variable)[[:space:]]+(set|delete|remove)([[:space:]]|$)" && deny "secret/variable change"

        write=0
        if has "$seg" "${GH}api([[:space:]]|$)"; then
            method="$(printf '%s\n' "$seg" | sed -nE 's/.*(-X|--method)[[:space:]=]*([A-Za-z]+).*/\2/p' | tr '[:lower:]' '[:upper:]')"
            if [ -z "$method" ]; then
                if has "$seg" '[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$)'; then method=POST; else method=GET; fi
            fi
            if [ "$method" != GET ] && ! has "$seg" "${GH}api[[:space:]]+['\"]?graphql"; then
                write=1
                has "$seg" '/pulls/[0-9]+/merge|/merges([[:space:]?'\''"]|$)' && deny "merge via gh api"
                has "$seg" '/(issues|pulls)/[0-9]+/(comments|reviews)|/(issues|pulls)/comments/|/commits/[^/[:space:]]+/comments' && deny "comment/review via gh api"
                has "$seg" '/(issues|pulls)/[0-9]+' && has "$seg" 'state=closed' && deny "closing a PR or issue via gh api"
                has "$seg" '/git/tags|/releases' && deny "tag or release via gh api"
                has "$seg" '/git/refs' && has "$seg" 'refs/tags/' && deny "tag ref via gh api"
                has "$seg" '/branches/[^[:space:]]*/protection|/rulesets|/environments|/secrets|/variables|/collaborators|/invitations|/hooks|/keys|/actions/permissions|/pages|/topics|/transfer|/teams|/autolinks|/vulnerability-alerts|/automated-security-fixes|/properties/values' \
                    && deny "repository settings change via gh api"
                has "$seg" "(^|[[:space:]'\"/])repos/[^/[:space:]]+/[^/[:space:]?'\"]+/?([[:space:]?'\"]|$)" && deny "repository settings change via gh api"
                has "$seg" "(^|[[:space:]'\"/])orgs/" && deny "organization change via gh api"
            fi
        elif ! has "$seg" "${GH}[a-z-]+[[:space:]]+(view|list|diff|checks|status|clone|download|watch|browse)([[:space:]]|$)" \
            && ! has "$seg" "${GH}(search|browse|auth|help|version|--version)([[:space:]]|$)"; then
            write=1
        fi
        [ "$write" = 1 ] && has "$seg" "$CRUNCHY|$OPENSHIFT_CRUNCHY" && deny "write touching crunchy"
    fi

    # ── git ──────────────────────────────────────────────────────────────────
    if has "$seg" "$GITCMD"; then
        gdir="$(printf '%s\n' "$seg" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p')"
        case "$gdir" in
            "") gdir="$dir" ;;
            "~"*) gdir="${HOME}${gdir#\~}" ;;
            /*) ;;
            *) gdir="$dir/$gdir" ;;
        esac

        if has "$seg" "${GITCMD}push([[:space:]]|$)"; then
            has "$seg" '[[:space:]](-[A-Za-z]*f[A-Za-z]*|--force|--force-with-lease(=[^[:space:]]*)?|--force-if-includes|--mirror)([[:space:]]|$)|[[:space:]]\+[^[:space:]]' \
                && deny "force push"
            has "$seg" '[[:space:]](--tags|--follow-tags)([[:space:]]|$)|refs/tags/|[[:space:]]tag[[:space:]]' && deny "pushing tags"
        fi
        has "$seg" "${GITCMD}tag[[:space:]]+([^-[:space:]]|(-a|-s|-u|-f|-d|-m|-F|--annotate|--sign|--force|--delete|--message|--file)([[:space:]=]|$))" \
            && deny "creating or deleting tags"

        if has "$seg" "${GITCMD}(push|commit|tag|merge|rebase|cherry-pick|revert|am|reset)([[:space:]]|$)"; then
            origin="$(origin_of "$gdir")"
            has "$origin" "$CRUNCHY" && deny "git write in bcgov/action-crunchy"
            if has "$origin" 'bcgov/actions-openshift'; then
                if has "$seg" "${GITCMD}commit([[:space:]]|$)"; then
                    changed="$(git -C "$gdir" diff --cached --name-only 2>/dev/null)"
                    has "$seg" '[[:space:]](-a|--all|-[A-Za-z]*a[A-Za-z]*)([[:space:]]|$)' \
                        && changed="$changed$newline$(git -C "$gdir" diff --name-only 2>/dev/null)"
                    has "$changed" '^crunchy/' && deny "commit touching crunchy/ in bcgov/actions-openshift"
                fi
                if has "$seg" "${GITCMD}push([[:space:]]|$)"; then
                    base="$(git -C "$gdir" rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)"
                    changed="$(git -C "$gdir" diff --name-only "$base...HEAD" 2>/dev/null)"
                    has "$changed" '^crunchy/' && deny "push touching crunchy/ in bcgov/actions-openshift"
                fi
            fi
        fi
    fi
    IFS="$newline"
done
IFS="$IFS_OLD"

allow
