#!/bin/bash
# Daily Summary — sends a summary of today's activity to General (thread 1)
# Usage: ./daily-summary.sh [agent_id]
# Default agent: or

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_FILE="$SWARM_DIR/tasks.json"
SEND="$SWARM_DIR/send.sh"
AGENT="${1:-or}"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$SWARM_DIR/logs/$TODAY.jsonl"

# Count completed today
DONE_COUNT=$(jq -r --arg today "$TODAY" '[.completed[] | select(.completedAt | startswith($today))] | length' "$TASKS_FILE")
DONE_LIST=$(jq -r --arg today "$TODAY" '.completed[] | select(.completedAt | startswith($today)) | "  ✅ #\(.id) \(.agent) — \(.title)"' "$TASKS_FILE")

# Count active
ACTIVE_COUNT=$(jq -r '[.tasks[] | select(.status == "active")] | length' "$TASKS_FILE")
ACTIVE_LIST=$(jq -r '.tasks[] | select(.status == "active") | "  ▶️ #\(.id) \(.agent) — \(.title)"' "$TASKS_FILE")

# Count stuck
STUCK_COUNT=$(jq -r '[.tasks[] | select(.status == "stuck")] | length' "$TASKS_FILE")
STUCK_LIST=$(jq -r '.tasks[] | select(.status == "stuck") | "  ⚠️ #\(.id) \(.agent) — \(.title) (\(.stuckReason))"' "$TASKS_FILE")

# Count messages sent today
if [ -f "$LOG_FILE" ]; then
  MSG_COUNT=$(wc -l < "$LOG_FILE")
else
  MSG_COUNT=0
fi

# Build summary
SUMMARY="📊 <b>סיכום יומי — $TODAY</b>

<b>הושלמו היום:</b> $DONE_COUNT משימות"

if [ -n "$DONE_LIST" ]; then
  SUMMARY="$SUMMARY
$DONE_LIST"
fi

SUMMARY="$SUMMARY

<b>פעילות:</b> $ACTIVE_COUNT משימות פעילות"
if [ -n "$ACTIVE_LIST" ]; then
  SUMMARY="$SUMMARY
$ACTIVE_LIST"
fi

if [ "$STUCK_COUNT" -gt 0 ]; then
  SUMMARY="$SUMMARY

<b>תקועות:</b> $STUCK_COUNT
$STUCK_LIST"
fi

SUMMARY="$SUMMARY

<b>הודעות היום:</b> $MSG_COUNT
⏰ $(date '+%H:%M')"

# Send to General — forum General topic requires NO thread_id
# send.sh always sets message_thread_id, so we send directly here
TOKEN=$(cat "$SWARM_DIR/.bot-token")
case "$AGENT" in
  shomer) TOKEN=$(cat "$SWARM_DIR/.shomer-token") ;;
  koder)  TOKEN=$(cat "$SWARM_DIR/.koder-token") ;;
  tzayar) TOKEN=$(cat "$SWARM_DIR/.tzayar-token") ;;
  worker) TOKEN=$(cat "$SWARM_DIR/.worker-token") ;;
esac
CHAT_ID="-1003815143703"
curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg chat "$CHAT_ID" --arg text "$SUMMARY" \
    '{chat_id: $chat, text: $text, parse_mode: "HTML"}')"
