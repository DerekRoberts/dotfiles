#!/bin/bash
# Sync agent instructions into the global prompt hub.
# Fetches instructions from dotfiles (local) or GitHub (remote).
#
# Usage: ./scripts/bundle-ai-instructions.sh
#
# Overrides (local dev only):
#   INSTRUCTIONS_URL=file:///path/to/instructions.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

INSTRUCTIONS_URL="${INSTRUCTIONS_URL:-$DOTFILES_DIR/config/ai/instructions.md}"
OUTPUT_FILE="${GLOBAL_INSTRUCTIONS_OUTPUT:-$HOME/.config/Code/User/prompts/global.instructions.md}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTRUCTIONS_FILE=""
INSTRUCTIONS_TEMP=""

cleanup() {
  if [[ -n "$INSTRUCTIONS_TEMP" && -f "$INSTRUCTIONS_TEMP" ]]; then
    rm -f "$INSTRUCTIONS_TEMP"
  fi
}
trap cleanup EXIT

# Fetch Instructions
if [[ "$INSTRUCTIONS_URL" == file://* ]]; then
  INSTRUCTIONS_FILE="${INSTRUCTIONS_URL#file://}"
  INSTRUCTIONS_SOURCE="$INSTRUCTIONS_FILE"
elif [[ -f "$INSTRUCTIONS_URL" ]]; then
  INSTRUCTIONS_FILE="$INSTRUCTIONS_URL"
  INSTRUCTIONS_SOURCE="$INSTRUCTIONS_FILE"
else
  INSTRUCTIONS_TEMP="$(mktemp)"
  INSTRUCTIONS_FILE="$INSTRUCTIONS_TEMP"
  INSTRUCTIONS_SOURCE="$INSTRUCTIONS_URL"
  if ! curl -fsSL --connect-timeout 15 "$INSTRUCTIONS_URL" -o "$INSTRUCTIONS_FILE"; then
    echo -e "${RED}ERROR:${NC} Failed to fetch instructions from $INSTRUCTIONS_URL" >&2
    exit 1
  fi
fi

if [[ ! -s "$INSTRUCTIONS_FILE" ]]; then
  echo -e "${RED}ERROR:${NC} Instructions empty at $INSTRUCTIONS_SOURCE" >&2
  exit 1
fi

echo -e "${BLUE}Syncing instructions...${NC}"
echo -e "   Source: $INSTRUCTIONS_SOURCE ($(wc -m < "$INSTRUCTIONS_FILE") chars)"
echo -e "   Hub:    $OUTPUT_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"

ACTION=$(python3 - "$INSTRUCTIONS_FILE" "$OUTPUT_FILE" <<'PY'
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

new_content = source_path.read_text(encoding="utf-8").rstrip() + "\n"

def normalize(text: str) -> str:
    return text.rstrip() + "\n"

if output_path.exists():
    current_content = output_path.read_text(encoding="utf-8")
else:
    current_content = ""

if normalize(current_content) == normalize(new_content):
    print("unchanged")
else:
    output_path.write_text(new_content, encoding="utf-8")
    print("updated")
PY
)

case "$ACTION" in
  unchanged)
    echo -e "${GREEN}✓${NC} Instructions already up to date in $OUTPUT_FILE"
    ;;
  updated)
    echo -e "${GREEN}✓${NC} Updated instructions in $OUTPUT_FILE"
    ;;
  *)
    echo -e "${RED}ERROR:${NC} Unexpected sync result: $ACTION" >&2
    exit 1
    ;;
esac

TOTAL_CHARS=$(($(wc -m < "$OUTPUT_FILE")))
echo -e "   Total: $TOTAL_CHARS chars in hub"

if [[ "$TOTAL_CHARS" -gt 8000 ]]; then
  echo -e "   ${YELLOW}Warning:${NC} Hub > 8,000 chars may reduce agent focus."
fi
