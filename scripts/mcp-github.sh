#!/usr/bin/env bash
# mcp-github — launch @modelcontextprotocol/server-github with an in-memory
# token from `gh auth token` so no plaintext PAT is persisted in mcp_config.json.
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

if ! command -v npx >/dev/null 2>&1; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # nvm.sh is not nounset-safe
        set +u
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        nvm use default >/dev/null 2>&1 || nvm use --lts >/dev/null 2>&1 || true
        set -u
    fi
fi

command -v npx >/dev/null 2>&1 || { echo "mcp-github: npx not found on PATH" >&2; exit 127; }
command -v gh >/dev/null 2>&1 || { echo "mcp-github: gh not found on PATH" >&2; exit 127; }

token="$(unset GITHUB_TOKEN GH_TOKEN; gh auth token --hostname github.com 2>/dev/null || true)"
[[ -n "$token" ]] || { echo "mcp-github: no active gh login; run 'gh auth login'" >&2; exit 1; }

export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
exec npx -y "@modelcontextprotocol/server-github@2025.4.8" "$@"
