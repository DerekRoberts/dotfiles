#!/bin/bash
# Sync personal instructions into the global prompt hub (delimiter-managed block).
# Fetches canonical personal text from GitHub main (strict online source).
# Work standards in the hub are owned elsewhere (org Copilot / VS Code).
#
# Usage: ./scripts/bundle-ai-instructions.sh
#
# Override (local dev only):
#   PERSONAL_INSTRUCTIONS_URL=file:///path/to/personal.instructions.md

set -euo pipefail

PERSONAL_URL="${PERSONAL_INSTRUCTIONS_URL:-https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/config/ai/personal.instructions.md}"
OUTPUT_FILE="${GLOBAL_INSTRUCTIONS_OUTPUT:-$HOME/.config/Code/User/prompts/global.instructions.md}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PERSONAL_FILE=""
PERSONAL_TEMP=""
cleanup() {
  if [[ -n "$PERSONAL_TEMP" && -f "$PERSONAL_TEMP" ]]; then
    rm -f "$PERSONAL_TEMP"
  fi
}
trap cleanup EXIT

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

echo -e "${BLUE}Syncing personal instructions...${NC}"
echo -e "   Source:   $PERSONAL_SOURCE ($(wc -m < "$PERSONAL_FILE") chars)"
echo -e "   Hub:      $OUTPUT_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"

ACTION=$(python3 - "$PERSONAL_FILE" "$OUTPUT_FILE" <<'PY'
import re
import sys
from pathlib import Path

START = "<!-- dotfiles:personal-instructions:start -->"
END = "<!-- dotfiles:personal-instructions:end -->"
LEGACY_HEADER = "# Personal Instructions (Derek)"

personal_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

personal = personal_path.read_text().rstrip() + "\n"

def wrap(body: str) -> str:
    return f"\n{START}\n{body.rstrip()}\n{END}\n"

def normalize(text: str) -> str:
    return text.rstrip() + "\n"

def extract_delimited(text: str) -> str | None:
    pattern = (
        re.escape(START) + r"\n(.*?)\n" + re.escape(END)
    )
    match = re.search(pattern, text, flags=re.DOTALL)
    return match.group(1) if match else None

def strip_delimited(text: str) -> str:
    pattern = re.escape(START) + r"\n.*?\n" + re.escape(END) + r"\n?"
    return re.sub(pattern, "", text, flags=re.DOTALL)

def strip_legacy_personal(text: str) -> str:
    idx = text.find(LEGACY_HEADER)
    if idx == -1:
        return text
    return text[:idx].rstrip()

def write_output(base: str, action: str) -> None:
    block = wrap(personal)
    if base:
        output_path.write_text(base.rstrip() + block)
    else:
        output_path.write_text(block.lstrip("\n"))
    print(action)

text = output_path.read_text() if output_path.exists() else ""
current = extract_delimited(text)

if current is not None:
    if normalize(current) == normalize(personal):
        print("unchanged")
    else:
        base = strip_delimited(text).rstrip()
        write_output(base, "updated")
elif LEGACY_HEADER in text:
    legacy_body = text[text.find(LEGACY_HEADER):]
    if normalize(legacy_body) == normalize(personal):
        base = strip_legacy_personal(text).rstrip()
        write_output(base, "upgraded")
    else:
        base = strip_legacy_personal(text).rstrip()
        write_output(base, "updated")
elif text and normalize(personal) in normalize(text):
    print("unchanged")
else:
    base = text.rstrip() if text else ""
    write_output(base, "appended" if text else "created")
PY
)

case "$ACTION" in
  unchanged)
    echo -e "${GREEN}✓${NC} Personal instructions already up to date in $OUTPUT_FILE"
    ;;
  upgraded)
    echo -e "${GREEN}✓${NC} Upgraded legacy personal block to delimited section in $OUTPUT_FILE"
    ;;
  updated)
    echo -e "${GREEN}✓${NC} Replaced stale personal instructions in $OUTPUT_FILE"
    ;;
  appended)
    echo -e "${GREEN}✓${NC} Appended personal instructions to $OUTPUT_FILE"
    ;;
  created)
    echo -e "${YELLOW}Note:${NC} Global hub did not exist — created $OUTPUT_FILE with personal block only."
    echo -e "       Work standards come from org Copilot / VS Code."
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
