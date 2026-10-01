#!/usr/bin/env bash
# test-git-identity.sh — shell-startup git identity, as examples.
# Usage: bash scripts/test-git-identity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# Never touch the real ~/.gitconfig. GIT_CONFIG_GLOBAL wins for --global.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL || true
: > "$GIT_CONFIG_GLOBAL"

real_before=""
if [[ -f "$HOME/.gitconfig" ]]; then
    real_before="$(sha256sum "$HOME/.gitconfig" | awk '{print $1}')"
fi

# shellcheck disable=SC1091
. "$ROOT/config/bashrc"

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }

email="$(command git config --global --get user.email)"
name="$(command git config --global --get user.name)"
if [[ "$name" == "Derek Roberts" && "$email" == "DerekRoberts@users.noreply.github.com" ]]; then
    ok "empty identity becomes noreply"
else
    bad "empty identity becomes noreply ($name <$email>)"
fi

printf '%s\n' "cursoragent@cursor.com" > "$TMP/cursor.pub"
printf '%s\n' "derek.roberts@gmail.com" > "$TMP/derek.pub"

repo="$TMP/repo"
command git init -q "$repo"
mkdir -p "$repo/.git/hooks" "$TMP/githooks"
printf '%s\n' '#!/bin/sh' > "$repo/.git/hooks/commit-msg.cursor.co-author"
printf '%s\n' '#!/bin/sh' > "$repo/.git/hooks/commit-msg.cursor"
printf '%s\n' '#!/bin/sh' > "$repo/.git/hooks/pre-commit.cursor"
chmod +x "$repo/.git/hooks/commit-msg.cursor.co-author" \
    "$repo/.git/hooks/commit-msg.cursor" \
    "$repo/.git/hooks/pre-commit.cursor"
command git config --global core.hooksPath "$TMP/githooks"

command git config --global user.name "Cursor Agent"
command git config --global user.email "cursoragent@cursor.com"
command git config --global user.signingkey "$TMP/cursor.pub"
command git config --global commit.gpgsign true
export GIT_AUTHOR_NAME="Cursor Agent"
export GIT_AUTHOR_EMAIL="cursoragent@cursor.com"
export GIT_COMMITTER_NAME="Cursor Agent"
export GIT_COMMITTER_EMAIL="cursoragent@cursor.com"
pushd "$repo" >/dev/null
reassert_git_identity
popd >/dev/null

email="$(command git config --global --get user.email)"
sign="$(command git config --global --get commit.gpgsign)"
if [[ "$email" == "DerekRoberts@users.noreply.github.com" && "$sign" == "false" \
    && "$GIT_AUTHOR_NAME" == "Derek Roberts" \
    && "$GIT_AUTHOR_EMAIL" == "DerekRoberts@users.noreply.github.com" \
    && "$GIT_COMMITTER_NAME" == "Derek Roberts" \
    && "$GIT_COMMITTER_EMAIL" == "DerekRoberts@users.noreply.github.com" \
    && ! -x "$repo/.git/hooks/commit-msg.cursor.co-author" \
    && -x "$repo/.git/hooks/commit-msg.cursor" \
    && -x "$repo/.git/hooks/pre-commit.cursor" ]]; then
    ok "cursor identity replaced, co-author hook disabled"
else
    bad "cursor identity replaced, co-author hook disabled"
fi

# Derek's key stays, even if the name was overwritten to Cursor Agent.
command git config --global user.name "Cursor Agent"
command git config --global user.email "cursoragent@cursor.com"
command git config --global user.signingkey "$TMP/derek.pub"
command git config --global commit.gpgsign true
reassert_git_identity
sign="$(command git config --global --get commit.gpgsign)"
key="$(command git config --global --get user.signingkey)"
if [[ "$sign" == "true" && "$key" == "$TMP/derek.pub" ]]; then
    ok "real signing key left enabled"
else
    bad "real signing key left enabled (sign=$sign key=$key)"
fi

command git config --global user.name "Derek Roberts"
command git config --global user.email "derek.roberts@gmail.com"
command git config --global user.signingkey "$TMP/derek.pub"
command git config --global commit.gpgsign true
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
reassert_git_identity
email="$(command git config --global --get user.email)"
sign="$(command git config --global --get commit.gpgsign)"
key="$(command git config --global --get user.signingkey)"
if [[ "$email" == "derek.roberts@gmail.com" && "$sign" == "true" && "$key" == "$TMP/derek.pub" \
    && -z "${GIT_AUTHOR_NAME:-}" ]]; then
    ok "existing Derek identity kept"
else
    bad "existing Derek identity kept (email=$email sign=$sign)"
fi

# Co-author hook on the active hooks path, not only .git/hooks.
printf '%s\n' '#!/bin/sh' > "$TMP/githooks/commit-msg.cursor.co-author"
printf '%s\n' '#!/bin/sh' > "$TMP/githooks/commit-msg.cursor"
chmod +x "$TMP/githooks/commit-msg.cursor.co-author" "$TMP/githooks/commit-msg.cursor"
pushd "$repo" >/dev/null
reassert_git_identity
popd >/dev/null
if [[ ! -x "$TMP/githooks/commit-msg.cursor.co-author" && -x "$TMP/githooks/commit-msg.cursor" ]]; then
    ok "hooksPath co-author hook disabled"
else
    bad "hooksPath co-author hook disabled"
fi

# Inline Cursor public key (no file) is still Cursor's signer.
command git config --global user.signingkey "cursoragent@cursor.com"
command git config --global commit.gpgsign true
reassert_git_identity
sign="$(command git config --global --get commit.gpgsign)"
if [[ "$sign" == "false" ]]; then
    ok "inline cursor key disables gpgsign"
else
    bad "inline cursor key disables gpgsign (sign=$sign)"
fi

if [[ -n "$real_before" ]]; then
    real_after="$(sha256sum "$HOME/.gitconfig" | awk '{print $1}')"
    if [[ "$real_before" == "$real_after" ]]; then
        ok "real gitconfig untouched"
    else
        bad "real gitconfig untouched"
    fi
fi

exit "$fails"
