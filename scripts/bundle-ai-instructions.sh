#!/bin/bash
# Sync work standards and personal instructions into the global prompt hub.
# Fetches upstream standards from GitHub (online) and personal text from dotfiles.
#
# Usage: ./scripts/bundle-ai-instructions.sh
#
# Overrides (local dev only):
#   STANDARDS_INSTRUCTIONS_URL=file:///path/to/copilot-instructions.md
#   PERSONAL_INSTRUCTIONS_URL=file:///path/to/personal.instructions.md

set -euo pipefail

STANDARDS_URL="${STANDARDS_INSTRUCTIONS_URL:-https://raw.githubusercontent.com/bcgov/copilot-instructions/main/copilot-instructions.md}"
PERSONAL_URL="${PERSONAL_INSTRUCTIONS_URL:-https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/config/ai/personal.instructions.md}"
OUTPUT_FILE="${GLOBAL_INSTRUCTIONS_OUTPUT:-$HOME/.config/Code/User/prompts/global.instructions.md}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STANDARDS_FILE=""
STANDARDS_TEMP=""
PERSONAL_FILE=""
PERSONAL_TEMP=""

cleanup() {
  if [[ -n "$STANDARDS_TEMP" && -f "$STANDARDS_TEMP" ]]; then
    rm -f "$STANDARDS_TEMP"
  fi
  if [[ -n "$PERSONAL_TEMP" && -f "$PERSONAL_TEMP" ]]; then
    rm -f "$PERSONAL_TEMP"
  fi
}
trap cleanup EXIT

# Fetch Standards Instructions
if [[ "$STANDARDS_URL" == file://* ]]; then
  STANDARDS_FILE="${STANDARDS_URL#file://}"
  STANDARDS_SOURCE="$STANDARDS_FILE"
elif [[ -f "$STANDARDS_URL" ]]; then
  STANDARDS_FILE="$STANDARDS_URL"
  STANDARDS_SOURCE="$STANDARDS_FILE"
else
  STANDARDS_TEMP="$(mktemp)"
  STANDARDS_FILE="$STANDARDS_TEMP"
  STANDARDS_SOURCE="$STANDARDS_URL"
  if ! curl -fsSL --connect-timeout 15 "$STANDARDS_URL" -o "$STANDARDS_FILE"; then
    echo -e "${RED}ERROR:${NC} Failed to fetch standards instructions from $STANDARDS_URL" >&2
    exit 1
  fi
fi

if [[ ! -s "$STANDARDS_FILE" ]]; then
  echo -e "${RED}ERROR:${NC} Standards instructions empty at $STANDARDS_SOURCE" >&2
  exit 1
fi

# Fetch Personal Instructions
if [[ "$PERSONAL_URL" == file://* ]]; then
  PERSONAL_FILE="${PERSONAL_URL#file://}"
  PERSONAL_SOURCE="$PERSONAL_FILE"
elif [[ -f "$PERSONAL_URL" ]]; then
  PERSONAL_FILE="$PERSONAL_URL"
  PERSONAL_SOURCE="$PERSONAL_FILE"
else
  PERSONAL_TEMP="$(mktemp)"
  PERSONAL_FILE="$PERSONAL_TEMP"
  PERSONAL_SOURCE="$PERSONAL_URL"
  if ! curl -fsSL --connect-timeout 15 "$PERSONAL_URL" -o "$PERSONAL_FILE"; then
    echo -e "${RED}ERROR:${NC} Failed to fetch personal instructions from $PERSONAL_URL" >&2
    echo "         Push config/ai/personal.instructions.md to main, or set PERSONAL_INSTRUCTIONS_URL for local dev." >&2
    exit 1
  fi
fi

if [[ ! -s "$PERSONAL_FILE" ]]; then
  echo -e "${RED}ERROR:${NC} Personal instructions empty at $PERSONAL_SOURCE" >&2
  exit 1
fi

echo -e "${BLUE}Syncing instructions...${NC}"
echo -e "   Standards: $STANDARDS_SOURCE ($(wc -m < "$STANDARDS_FILE") chars)"
echo -e "   Personal:  $PERSONAL_SOURCE ($(wc -m < "$PERSONAL_FILE") chars)"
echo -e "   Hub:       $OUTPUT_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"

ACTION=$(python3 - "$STANDARDS_FILE" "$PERSONAL_FILE" "$OUTPUT_FILE" <<'PY'
import sys
from pathlib import Path

standards_path = Path(sys.argv[1])
personal_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

standards = standards_path.read_text().rstrip() + "\n"
personal = personal_path.read_text().rstrip() + "\n"

new_content = standards + "\n" + personal

def normalize(text: str) -> str:
    return text.rstrip() + "\n"

if output_path.exists():
    current_content = output_path.read_text()
else:
    current_content = ""

if normalize(current_content) == normalize(new_content):
    print("unchanged")
else:
    output_path.write_text(new_content)
    print("updated")
PY
)

case "$ACTION" in
  unchanged)
    echo -e "${GREEN}✓${NC} Instructions already up to date in $OUTPUT_FILE"
    ;;
  updated)
    echo -e "${GREEN}✓${NC} Concatenated and updated instructions in $OUTPUT_FILE"
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

