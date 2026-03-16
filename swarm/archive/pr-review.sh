#!/bin/bash
# pr-review.sh — Send PR with inline approve/reject buttons
# Usage: pr-review.sh TASK_ID DESCRIPTION
TASK_ID="$1"
DESC="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$TASK_ID" ] || [ -z "$DESC" ]; then
  echo "Usage: pr-review.sh TASK_ID DESCRIPTION"
  exit 1
fi

TOKEN=$(cat "$SCRIPT_DIR/.bot-token")
CHAT_ID="-1003815143703"
SCREENSHOT="/tmp/task-${TASK_ID}-pipeline.png"

CAPTION="📋 PR #${TASK_ID}: ${DESC}

לחץ לאשר או לדחות:"

KEYBOARD='{"inline_keyboard":[[{"text":"✅ Approve + Deploy","callback_data":"approve_'$TASK_ID'"},{"text":"❌ Reject","callback_data":"reject_'$TASK_ID'"}]]}'

if [ -f "$SCREENSHOT" ]; then
  curl -s "https://api.telegram.org/bot$TOKEN/sendPhoto" \
    -F "chat_id=$CHAT_ID" \
    -F "photo=@$SCREENSHOT" \
    -F "caption=$CAPTION" \
    -F "reply_markup=$KEYBOARD"
else
  curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$CHAT_ID\",\"text\":$(echo "$CAPTION" | jq -Rs .),\"reply_markup\":$KEYBOARD}"
fi
