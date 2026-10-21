#!/usr/bin/env bash
# gh wrapper — always use the local gh login, never an ambient token.
# Installed by setup as ~/.local/share/dotfiles/bin/gh, ahead of the real gh on PATH.
unset GITHUB_TOKEN GH_TOKEN
self="$(readlink -f "${BASH_SOURCE[0]}")"
real=""
while IFS= read -r candidate; do
    [[ "$(readlink -f "$candidate")" == "$self" ]] || { real="$candidate"; break; }
done < <(type -ap gh)
[[ -n "$real" ]] || { echo "gh wrapper: no real gh found on PATH" >&2; exit 127; }
exec "$real" "$@"
