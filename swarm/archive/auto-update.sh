#!/bin/bash
# auto-update.sh — Send completion notification to General
# Usage: swarm/auto-update.sh <agent_id> <thread_id> "summary" [status]
# status: done (default), fail, blocked

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="${1:?Usage: auto-update.sh <agent_id> <thread_id> <summary> [status]}"
THREAD_ID="${2:?Missing thread_id}"
SUMMARY="${3:?Missing summary}"
STATUS="${4:-done}"

case "$STATUS" in
  done)    EMOJI="✅"; LABEL="הושלם" ;;
  fail)    EMOJI="❌"; LABEL="נכשל" ;;
  blocked) EMOJI="🚧"; LABEL="חסום" ;;
  *)       EMOJI="📋"; LABEL="$STATUS" ;;
esac

# Get agent display name
case "$AGENT_ID" in
  shomer)     NAME="שומר 🔒" ;;
  koder)      NAME="קודר ⚙️" ;;
  tzayar)     NAME="צייר 🎨" ;;
  worker)     NAME="עובד 🤖" ;;
  researcher) NAME="חוקר 🔍" ;;
  *)          NAME="$AGENT_ID" ;;
esac

# Post to General (thread 1) as orchestrator
"$SWARM_DIR/send.sh" or 1 "$EMOJI <b>$NAME סיים משימה #$THREAD_ID</b> — $LABEL

$SUMMARY

$([ "$STATUS" = "done" ] && echo "🚀 לדחוף לפרודקשן?" || echo "")"

# Also update tasks.json
TASKS_FILE="$SWARM_DIR/tasks.json"
if [ -f "$TASKS_FILE" ] && command -v jq &>/dev/null; then
  TMP=$(mktemp)
  jq --arg tid "$THREAD_ID" --arg st "$STATUS" --arg ts "$(date -Iseconds)" \
    '(.[] | select(.thread_id == ($tid | tonumber) or .id == $tid)) |= . + {status: $st, completed_at: $ts}' \
    "$TASKS_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$TASKS_FILE" || rm -f "$TMP"
fi

# Kill progress reporter if running
PGREP=$(pgrep -f "progress.sh $AGENT_ID $THREAD_ID" 2>/dev/null)
if [ -n "$PGREP" ]; then
  kill $PGREP 2>/dev/null
  echo "Stopped progress reporter (PID $PGREP)"
fi

echo "Auto-update sent to General"
