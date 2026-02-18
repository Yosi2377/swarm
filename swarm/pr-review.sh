#!/bin/bash
# pr-review.sh TASK_ID DESCRIPTION
# Sends PR to General with inline Approve/Reject buttons
TASK_ID="$1"
DESC="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/.."

# Get diff stats
BRANCH="task-${TASK_ID}-*"
ACTUAL_BRANCH=$(git branch --list $BRANCH | head -1 | tr -d ' *')
DIFF=$(git diff master..$ACTUAL_BRANCH --stat 2>/dev/null | tail -3 || echo "no diff")

# Get screenshot from pipeline
SCREENSHOT="/tmp/task-${TASK_ID}-pipeline.png"

TOKEN=$(cat "$SCRIPT_DIR/.bot-token" 2>/dev/null || cat "$SCRIPT_DIR/.or-token" 2>/dev/null)
CHAT_ID="-1003815143703"

# Create inline keyboard JSON
KEYBOARD='{"inline_keyboard":[[{"text":"✅ Approve + Deploy","callback_data":"approve_'"$TASK_ID"'"},{"text":"❌ Reject","callback_data":"reject_'"$TASK_ID"'"}]]}'

# Send photo with inline buttons
if [ -f "$SCREENSHOT" ]; then
  CAPTION="📋 PR #${TASK_ID}: ${DESC}
📊 ${DIFF}

לחץ לאשר או לדחות:"

  curl -s "https://api.telegram.org/bot$TOKEN/sendPhoto" \
    -F "chat_id=$CHAT_ID" \
    -F "photo=@$SCREENSHOT" \
    -F "caption=$CAPTION" \
    -F "reply_markup=$KEYBOARD"
else
  # Text only
  MSG="📋 PR #${TASK_ID}: ${DESC}
📊 ${DIFF}

לחץ לאשר או לדחות:"

  curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$CHAT_ID\",\"text\":$(echo "$MSG" | jq -Rs .),\"reply_markup\":$KEYBOARD}"
fi
