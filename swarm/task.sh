#!/bin/bash
# Task Manager CLI
# Usage:
#   ./task.sh add <agent> <thread_id> <title> [priority]
#   ./task.sh done <task_id> [summary]
#   ./task.sh stuck <task_id> [reason]
#   ./task.sh status [agent]
#   ./task.sh list

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_FILE="$SWARM_DIR/tasks.json"
ACTION="$1"

# Ensure tasks.json exists
if [ ! -f "$TASKS_FILE" ]; then
  echo '{"version":2,"tasks":[],"completed":[],"nextId":1}' > "$TASKS_FILE"
fi

case "$ACTION" in
  add)
    AGENT="$2"
    THREAD="$3"
    TITLE="$4"
    PRIORITY="${5:-medium}"
    NEXT_ID=$(jq '.nextId' "$TASKS_FILE")
    NOW=$(date -Iseconds)
    
    jq --arg agent "$AGENT" --argjson thread "$THREAD" --arg title "$TITLE" \
       --arg priority "$PRIORITY" --arg now "$NOW" --argjson id "$NEXT_ID" \
       '.tasks += [{id: $id, agent: $agent, thread: $thread, title: $title, 
         priority: $priority, status: "active", startedAt: $now, updatedAt: $now}] 
       | .nextId = ($id + 1)' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    echo "Task #$NEXT_ID created: $TITLE → $AGENT (thread $THREAD)"
    ;;
    
  done)
    TASK_ID="$2"
    SUMMARY="${3:-completed}"
    NOW=$(date -Iseconds)
    
    # Move from tasks to completed
    TASK=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [ -z "$TASK" ]; then
      echo "Task #$TASK_ID not found"
      exit 1
    fi
    
    jq --argjson id "$TASK_ID" --arg summary "$SUMMARY" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)) as $t |
        .completed += [$t + {status: "done", summary: $summary, completedAt: $now}] |
        .tasks = [.tasks[] | select(.id != $id)]' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    echo "Task #$TASK_ID marked done"
    ;;
    
  stuck)
    TASK_ID="$2"
    REASON="${3:-unknown}"
    NOW=$(date -Iseconds)
    
    jq --argjson id "$TASK_ID" --arg reason "$REASON" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)).status = "stuck" |
        (.tasks[] | select(.id == $id)).stuckReason = $reason |
        (.tasks[] | select(.id == $id)).updatedAt = $now' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    echo "Task #$TASK_ID marked stuck: $REASON"
    ;;
    
  status)
    AGENT_FILTER="$2"
    if [ -n "$AGENT_FILTER" ]; then
      jq -r --arg a "$AGENT_FILTER" '.tasks[] | select(.agent == $a) | 
        "#\(.id) [\(.status)] \(.title) (thread \(.thread))"' "$TASKS_FILE"
    else
      echo "=== Active Tasks ==="
      jq -r '.tasks[] | "#\(.id) \(.agent) [\(.status)] \(.title) (thread \(.thread))"' "$TASKS_FILE"
      echo ""
      echo "=== Recently Completed ==="
      jq -r '.completed[-5:][] | "#\(.id) \(.agent) ✅ \(.title)"' "$TASKS_FILE"
    fi
    ;;
    
  list)
    jq '.' "$TASKS_FILE"
    ;;
    
  board)
    # Generate status board text
    ACTIVE=$(jq -r '.tasks[] | select(.status == "active") | "▶️ #\(.id) \(.agent) — \(.title)"' "$TASKS_FILE")
    STUCK=$(jq -r '.tasks[] | select(.status == "stuck") | "⚠️ #\(.id) \(.agent) — \(.title) (\(.stuckReason))"' "$TASKS_FILE")
    DONE_TODAY=$(jq -r --arg today "$(date +%Y-%m-%d)" '.completed[] | select(.completedAt | startswith($today)) | "✅ #\(.id) \(.agent) — \(.title)"' "$TASKS_FILE")
    
    BOARD="📊 <b>סטטוס בורד — $(date '+%H:%M %d/%m')</b>\n\n"
    
    if [ -n "$ACTIVE" ]; then
      BOARD+="<b>🔄 פעיל:</b>\n$ACTIVE\n\n"
    else
      BOARD+="<b>🔄 פעיל:</b>\nאין משימות פעילות\n\n"
    fi
    
    if [ -n "$STUCK" ]; then
      BOARD+="<b>⚠️ תקוע:</b>\n$STUCK\n\n"
    fi
    
    if [ -n "$DONE_TODAY" ]; then
      BOARD+="<b>✅ הושלם היום:</b>\n$DONE_TODAY"
    fi
    
    echo -e "$BOARD"
    ;;
    
  history)
    jq -r '.completed | reverse | .[:20][] | 
      "#\(.id) | \(.agent) | \(.title) | thread \(.thread) | \(.completedAt // "?")"' "$TASKS_FILE"
    ;;
    
  *)
    echo "Usage: task.sh {add|done|stuck|status|list|board|history}"
    echo "  add <agent> <thread> <title> [priority]"
    echo "  done <task_id> [summary]"
    echo "  stuck <task_id> [reason]"
    echo "  status [agent]"
    echo "  list    — raw JSON"
    echo "  board   — formatted status board"
    echo "  history — completed tasks"
    ;;
esac
