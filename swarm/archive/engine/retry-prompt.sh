#!/bin/bash
# retry-prompt.sh — Generate enriched retry prompt from failure
# Usage: retry-prompt.sh <original_prompt_file> <check_output> <attempt_number>
# Output: path to enriched prompt file
set -euo pipefail

PROMPT_FILE="${1:?Usage: retry-prompt.sh <prompt_file> <check_output> <attempt>}"
CHECK_OUTPUT="${2:-unknown failure}"
ATTEMPT="${3:-2}"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

# Derive agent-thread from filename
BASENAME=$(basename "$PROMPT_FILE" .prompt)
# Strip existing -attemptN suffix
BASENAME=$(echo "$BASENAME" | sed 's/-attempt[0-9]*//')
mkdir -p /tmp/engine-tasks

RETRY_FILE="/tmp/engine-tasks/${BASENAME}-attempt${ATTEMPT}.prompt"

# Copy original prompt
cp "$PROMPT_FILE" "$RETRY_FILE"

# Append failure context
{
  echo ""
  echo "⚠️ ATTEMPT $ATTEMPT FAILED:"
  echo "$CHECK_OUTPUT"
  echo ""
  echo "Fix EXACTLY the issues above. Be specific. Do not repeat the same mistake."

  # Timeout-specific guidance
  if echo "$CHECK_OUTPUT" | grep -qi "timeout\|timed out"; then
    echo ""
    echo "PREVIOUS ATTEMPT TIMED OUT. Be faster. Skip exploration, go directly to the fix."
  fi

  # Content check failures — highlight exact content
  if echo "$CHECK_OUTPUT" | grep -qi "not found\|still present\|content"; then
    echo ""
    echo "CONTENT CHECK FAILED. Ensure the exact text changes are applied in the visible HTML."
    MISSING=$(echo "$CHECK_OUTPUT" | grep -oP "(?:Found|not found|still present).*" | head -3)
    [ -n "$MISSING" ] && echo "Details: $MISSING"
  fi
} >> "$RETRY_FILE"

echo "$RETRY_FILE"
