#!/bin/bash
# Thin wrapper: install bcgov/agent-guardrails from local clone or curl.
# Called from dotfiles/setup.sh — guardrails live in agent-guardrails, not dotfiles.

set -euo pipefail

AGENT_GUARDRAILS_DIR="${AGENT_GUARDRAILS_DIR:-$HOME/Repos/agent-guardrails}"
GUARDRAILS_SETUP="${AGENT_GUARDRAILS_DIR}/setup.sh"

if [[ -f "$GUARDRAILS_SETUP" ]]; then
  echo "Installing AI guardrails from $AGENT_GUARDRAILS_DIR..."
  bash "$GUARDRAILS_SETUP"
else
  echo "Local clone not found at $AGENT_GUARDRAILS_DIR — fetching from bcgov/agent-guardrails..."
  curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash
fi
