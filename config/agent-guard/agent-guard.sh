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
    esac
    exit 0
fi

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
        "gh api -X PUT"*"/merge"*)                        deny "merging a PR" ;;
        "gh api -X "*/protection*|"gh api -X "*/rulesets*|"gh api -X "*/collaborators*) deny "changing repo settings" ;;

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
