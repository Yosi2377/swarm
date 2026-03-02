#!/bin/bash
# notify.sh — Drop a notification marker + auto-trigger peer review on success
# Usage: notify.sh <thread_id> <status> <message> [agent]
# Status: success|failed|stuck|progress
# Example: notify.sh 4950 success "✅ תיקון הושלם" koder

DIR="$(cd "$(dirname "$0")" && pwd)"
DONE_DIR="/tmp/agent-done"
mkdir -p "$DONE_DIR"

THREAD="${1:?Usage: notify.sh <thread> <status> <message> [agent]}"
STATUS="${2:-done}"
MSG="${3:-סוכן סיים}"
AGENT="${4:-or}"
ID="$(date +%s)-$$"

# Use python3 for safe JSON serialization (handles quotes, special chars)
python3 -c "
import json, sys
data = {'thread': int(sys.argv[1]), 'status': sys.argv[2], 'message': sys.argv[3], 'agent': sys.argv[4], 'ts': sys.argv[5]}
with open(sys.argv[6], 'w') as f:
    json.dump(data, f, ensure_ascii=False)
" "$THREAD" "$STATUS" "$MSG" "$AGENT" "$(date -Iseconds)" "$DONE_DIR/${ID}.json"

echo "📝 Notification queued: $MSG"

# Auto-trigger peer review on success
if [ "$STATUS" = "success" ] || [ "$STATUS" = "done" ]; then
  # Find task ID from tasks.json
  TASKS_FILE="$DIR/tasks.json"
  TASK_ID=""
  if [ -f "$TASKS_FILE" ]; then
    TASK_ID=$(jq -r --argjson thread "$THREAD" '.tasks[] | select(.thread == $thread) | .id' "$TASKS_FILE" 2>/dev/null | head -1)
  fi
  
  if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]; then
    # Auto-trigger peer review
    echo "🔄 Triggering peer review for task #${TASK_ID}..."
    bash "$DIR/peer-review.sh" "$TASK_ID" "$AGENT" "$THREAD" 2>/dev/null
    
    # Update context to "review"
    case "$AGENT" in
      koder)      EMOJI="⚙️"; NAME="קודר" ;;
      shomer)     EMOJI="🔒"; NAME="שומר" ;;
      tzayar)     EMOJI="🎨"; NAME="צייר" ;;
      researcher) EMOJI="🔍"; NAME="חוקר" ;;
      worker)     EMOJI="🤖"; NAME="עובד" ;;
      bodek)      EMOJI="🧪"; NAME="בודק" ;;
      *)          EMOJI="🤖"; NAME="$AGENT" ;;
    esac
    bash "$DIR/context.sh" update "$EMOJI" "$NAME" "review" "Peer review pending" "$THREAD" 2>/dev/null
  else
    echo "⚠️ No task found in tasks.json for thread $THREAD — skipping peer review"
  fi
fi
