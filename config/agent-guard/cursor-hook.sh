#!/bin/sh
# Cursor adapter for agent-guard (beforeShellExecution, beforeMCPExecution).
# Reads Cursor's hook JSON on stdin, prints Cursor's permission JSON.
export PATH="${HOME}/.local/bin:${PATH}"

input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1 // empty"; }
allow() { echo '{"permission":"allow"}'; exit 0; }

case "$(field .hook_event_name)" in
    beforeShellExecution)
        reason="$(agent-guard shell "$(field .command)" "$(field .cwd)" 2>&1)" && allow ;;
    beforeMCPExecution)
        printf '%s' "$(field .mcp_server_name) $(field .url)" | grep -qi github || allow
        reason="$(agent-guard mcp "$(field .tool_name)" "$(field .tool_input)" 2>&1)" && allow ;;
    *) allow ;;
esac
jq -cn --arg m "$reason" '{permission: "deny", user_message: $m, agent_message: $m}'
