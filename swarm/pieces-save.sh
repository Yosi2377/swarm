#!/bin/bash
# Save task summary to Pieces LTM
# Usage: pieces-save.sh <agent_id> <thread_id> "summary"

AGENT="${1:-unknown}"
THREAD="${2:-0}"
SUMMARY="${3:-No summary}"
DATE=$(date '+%Y-%m-%d %H:%M')

# Create content
CONTENT="// Task #${THREAD} | Agent: ${AGENT} | ${DATE}
// ${SUMMARY}"

# Save to Pieces via clipboard + CLI
export DISPLAY=:1
echo "$CONTENT" | xclip -selection clipboard 2>/dev/null
echo "y" | pieces --ignore-onboarding create 2>/dev/null

# Also save via API as backup
curl -s -X POST http://localhost:39300/assets/create \
  -H "Content-Type: application/json" \
  -d "{\"seed\":{\"asset\":{\"application\":{\"id\":\"DEFAULT\"},\"format\":{\"fragment\":{\"string\":{\"raw\":\"$CONTENT\"}}},\"metadata\":{\"name\":\"Task #${THREAD} - ${AGENT}\"}}}}" \
  2>/dev/null > /dev/null

echo "✅ Saved to Pieces: Task #${THREAD}"
