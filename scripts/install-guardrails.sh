#!/bin/bash
# Install bcgov/agent-guardrails: local clone + run, or curl bootstrap.
# Guardrails are independent of dotfiles setup — run once, or when guardrails change.

set -euo pipefail

AGENT_GUARDRAILS_DIR="${AGENT_GUARDRAILS_DIR:-$HOME/Repos/agent-guardrails}"
GUARDRAILS_SETUP="${AGENT_GUARDRAILS_DIR}/setup.sh"

if [[ -f "$GUARDRAILS_SETUP" ]]; then
  echo "Installing AI guardrails from $AGENT_GUARDRAILS_DIR..."
  bash "$GUARDRAILS_SETUP"
else
  echo "Local clone not found at $AGENT_GUARDRAILS_DIR — bootstrapping via curl..."
  curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash
fi
