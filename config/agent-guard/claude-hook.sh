#!/bin/sh
# Claude Code adapter for agent-guard (PreToolUse on Bash and GitHub MCP tools).
# Reads Claude's hook JSON on stdin. agent-guard already follows Claude's
# convention (exit 2 = deny, reason on stderr), so a denial passes straight through.
export PATH="${HOME}/.local/bin:${PATH}"

input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1 // empty"; }

case "$(field .tool_name)" in
    Bash)
        exec agent-guard shell "$(field .tool_input.command)" "$(field .cwd)" ;;
    mcp__*github*__*)
        tool="$(field .tool_name)"
        exec agent-guard mcp "${tool##*__}" "$(field '.tool_input | tojson')" ;;
esac
exit 0
