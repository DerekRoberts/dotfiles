#!/bin/bash
# Sync unified AI instructions into the global prompt hub.
#
# Usage: ./scripts/bundle-ai-instructions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_INPUT="${INSTRUCTIONS_SOURCE:-$DOTFILES_DIR/config/ai/instructions.md}"
OUTPUT_FILE="${GLOBAL_INSTRUCTIONS_OUTPUT:-$HOME/.config/Code/User/prompts/global.instructions.md}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEMP_FILE=""
cleanup() {
  if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
    rm -f "$TEMP_FILE"
  fi
}
trap cleanup EXIT

if [[ "$SOURCE_INPUT" == file://* ]]; then
  SOURCE_FILE="${SOURCE_INPUT#file://}"
elif [[ -f "$SOURCE_INPUT" ]]; then
  SOURCE_FILE="$SOURCE_INPUT"
else
  TEMP_FILE="$(mktemp)"
  SOURCE_FILE="$TEMP_FILE"
  if ! curl -fsSL --connect-timeout 15 "$SOURCE_INPUT" -o "$SOURCE_FILE"; then
    echo -e "${RED}ERROR:${NC} Failed to fetch instructions from $SOURCE_INPUT" >&2
    exit 1
  fi
fi

if [[ ! -s "$SOURCE_FILE" ]]; then
  echo -e "${RED}ERROR:${NC} Instructions file empty at $SOURCE_INPUT" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [[ -f "$OUTPUT_FILE" ]] && cmp -s "$SOURCE_FILE" "$OUTPUT_FILE"; then
  echo -e "${GREEN}✓${NC} Instructions already up to date in $OUTPUT_FILE"
else
  cp "$SOURCE_FILE" "$OUTPUT_FILE"
  echo -e "${GREEN}✓${NC} Updated instructions in $OUTPUT_FILE"
fi

TOTAL_CHARS=$(wc -m < "$OUTPUT_FILE")
echo -e "   Total: $TOTAL_CHARS chars in hub"

if [[ "$TOTAL_CHARS" -gt 8000 ]]; then
  echo -e "   ${YELLOW}Warning:${NC} Hub > 8,000 chars may reduce agent focus."
fi
