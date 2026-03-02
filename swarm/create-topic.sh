#!/bin/bash
# create-topic.sh — Create a Telegram forum topic automatically
# Usage: create-topic.sh <name> [icon_color] [agent_id]
# Returns: thread_id (numeric) on stdout
#
# Icon colors (Telegram allowed values):
#   7322096 (green), 16766590 (yellow), 13338331 (violet),
#   9367192 (blue), 16749490 (red), 16478047 (orange)
#
# Agent auto-color mapping:
#   koder=blue, shomer=red, tzayar=violet, researcher=green, worker=orange, bodek=yellow
#
# Examples:
#   create-topic.sh "⚙️ Fix login bug"
#   create-topic.sh "🔒 Security audit" 16749490
#   THREAD=$(create-topic.sh "⚙️ Task: Fix odds" "" koder)

DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:?Usage: create-topic.sh <name> [icon_color] [agent_id]}"
ICON_COLOR="$2"
AGENT="${3:-}"
CHAT_ID="-1003815143703"

# Use orchestrator bot token for topic creation
TOKEN=$(cat "$DIR/.bot-token" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "ERROR: No bot token found" >&2
  exit 1
fi

# Auto-assign color by agent if not specified
if [ -z "$ICON_COLOR" ] && [ -n "$AGENT" ]; then
  case "$AGENT" in
    koder)      ICON_COLOR="9367192"  ;;  # blue
    shomer)     ICON_COLOR="16749490" ;;  # red
    tzayar)     ICON_COLOR="13338331" ;;  # violet
    researcher) ICON_COLOR="7322096"  ;;  # green
    worker)     ICON_COLOR="16478047" ;;  # orange
    bodek)      ICON_COLOR="16766590" ;;  # yellow
    *)          ICON_COLOR="9367192"  ;;  # blue default
  esac
fi

# Default color if still empty
ICON_COLOR="${ICON_COLOR:-9367192}"

# Create the topic via Telegram API
RESULT=$(curl -sf "https://api.telegram.org/bot${TOKEN}/createForumTopic" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json, sys
print(json.dumps({
    'chat_id': sys.argv[1],
    'name': sys.argv[2],
    'icon_color': int(sys.argv[3])
}))
" "$CHAT_ID" "$NAME" "$ICON_COLOR")" 2>/dev/null)

if [ -z "$RESULT" ]; then
  echo "ERROR: Telegram API call failed" >&2
  exit 1
fi

# Extract thread_id
THREAD_ID=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['message_thread_id'])" 2>/dev/null)

if [ -z "$THREAD_ID" ] || [ "$THREAD_ID" = "None" ]; then
  echo "ERROR: Could not extract thread_id from: $RESULT" >&2
  exit 1
fi

echo "$THREAD_ID"
