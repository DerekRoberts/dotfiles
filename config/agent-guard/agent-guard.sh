#!/bin/sh
# agent-guard — a readable reminder of the Hard Stops in config/instructions.md
# for a helpful AI agent that forgot one. Not security: it only knows the plain
# forms an agent would normally type.
#
#   agent-guard shell "<command>" [cwd]
#   agent-guard mcp "<tool_name>" "<args json>"
#
# Exit 0 = allow. Exit 2 = deny, reason on stderr.

deny() {
    echo "agent-guard: $1 needs the user's approval. Stop and ask the user instead." >&2
    exit 2
}

if [ "$1" = mcp ]; then
    tool="$2"
    case "$tool" in
        transfer_issue) ;;
        merge_pull_request)  deny "merging a PR" ;;
        *unresolve*)         deny "unresolving a review thread" ;;
        resolve_*|*resolve*thread*) ;;
        *comment*|*review*)  case "$tool" in list_*|get_*) ;; *) deny "commenting or reviewing" ;; esac ;;
        *secret*|update_repository*|delete_repository*) deny "changing repo settings" ;;
        update_issue|update_pull_request|issue_write|pull_request_write)
            case "$3" in *'"state"'*) deny "closing or reopening an issue or PR" ;; esac ;;
    esac
    exit 0
fi

# Reads a "gh api" command into: path (the endpoint), method (-X/--method,
# or POST when it sends fields with -f/-F/--input), and state (a field sets
# "state", i.e. closes or reopens).
gh_api() {
    path='' method='' fields='' state=''
    set -f
    # shellcheck disable=SC2086 # split into words on purpose
    set -- $1
    set +f
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            -X|--method)               method="$2"; shift ;;
            -X*)                       method="${1#-X}" ;;
            --method=*)                method="${1#*=}" ;;
            -f|-F|--field|--raw-field) fields=1
                                       case "$2" in state=*|[\"\']state=*) state=1 ;; esac; shift ;;
            -f*|-F*|--field=*|--raw-field=*)
                                       fields=1
                                       case "$1" in
                                           -f*) v="${1#-f}" ;;
                                           -F*) v="${1#-F}" ;;
                                           *)   v="${1#*=}" ;;
                                       esac
                                       case "$v" in state=*|[\"\']state=*) state=1 ;; esac ;;
            --input|--input=*)         fields=1; [ "$1" = --input ] && shift ;;
            -H|--header|-q|--jq|-t|--template|--hostname|--cache|-p|--preview) shift ;;
            -*) ;;
            *)                         [ -n "$path" ] || path="$1" ;;
        esac
        shift
    done
    [ -n "$method" ] || { [ -n "$fields" ] && method=POST; }
    method="$(printf '%s' "${method:-GET}" | tr '[:lower:]' '[:upper:]')"
}

cmd="$2" dir="${3:-$PWD}"

# One simple command per line, so a commit message that mentions
# "gh pr merge" is not mistaken for one.
printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g' | {
while read -r c; do
    case "$c" in
        "gh issue transfer"*) continue ;;

        "gh pr merge"*)                                   deny "merging a PR" ;;
        "gh pr comment"*|"gh pr review"*|"gh pr close"*)  deny "commenting on, reviewing, or closing a PR" ;;
        "gh issue comment"*|"gh issue close"*|"gh issue delete"*) deny "commenting on, closing, or deleting an issue" ;;
        "gh repo edit"*|"gh repo archive"*|"gh repo delete"*)     deny "changing repo settings" ;;
        "gh secret set"*|"gh secret delete"*|"gh variable set"*|"gh variable delete"*) deny "changing secrets or variables" ;;
        "gh api "*)
            gh_api "$c"
            case "$path" in
                graphql|[\"\']graphql[\"\'])
                    # Mutations by name; resolveReviewThread is allowed.
                    # GraphQL ignores whitespace around ":", so "state :" is "state:".
                    graphql_cmd="$(printf '%s' "$c" | sed -E 's/state[[:space:]]*:[[:space:]]*/state:/g')"
                    case "$graphql_cmd" in
                        *unresolveReviewThread*) deny "unresolving a review thread" ;;
                        *mergePullRequest*|*enablePullRequestAutoMerge*) deny "merging a PR" ;;
                        *addComment*|*updateIssueComment*|*deleteIssueComment*|*minimizeComment*) deny "commenting" ;;
                        *addPullRequestReview*|*submitPullRequestReview*|*dismissPullRequestReview*) deny "reviewing" ;;
                        *updatePullRequestReview*|*deletePullRequestReview*) deny "reviewing" ;;
                        *closeIssue*|*reopenIssue*|*deleteIssue*|*closePullRequest*|*reopenPullRequest*) deny "closing or reopening an issue or PR" ;;
                        *updateIssue*state:*|*updatePullRequest*state:*) deny "closing or reopening an issue or PR" ;;
                    esac
                    continue ;;
            esac
            [ "$method" = GET ] && continue
            case "$path" in
                */pulls/*/merge*)                          deny "merging a PR" ;;
                */comments*|*/reviews*)                    deny "commenting or reviewing" ;;
                */protection*|*/rulesets*|*/collaborators*) deny "changing repo settings" ;;
                */secrets*|*/variables*)                   deny "changing secrets or variables" ;;
                */issues/[0-9]*|*/pulls/[0-9]*)            [ -z "$state" ] || deny "closing or reopening an issue or PR" ;;
            esac ;;

        "git push"*" -f"|"git push"*" -f "*|"git push"*" --force"*) deny "force-pushing" ;;
        "git push"*" --tags"*)                            deny "pushing tags" ;;
        "git push"*)
            # A tag pushed by name, e.g. "git push origin v1.2.3" or "+v1:v1".
            for a in ${c#git push}; do
                a="${a#+}" a="${a%%:*}"
                case "$a" in
                    -*) ;;
                    refs/tags/*) deny "pushing tags" ;;
                    *) git -C "$dir" show-ref --verify --quiet "refs/tags/$a" 2>/dev/null && deny "pushing tags" ;;
                esac
            done ;;
        "git update-ref"*"refs/tags/"*)                   deny "creating a tag" ;;
        "git tag"|"git tag -l"*|"git tag --list"*)        ;;
        "git tag "*)                                      deny "creating a tag" ;;
    esac
done
exit 0
}
