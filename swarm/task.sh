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
    PRIORITY="${5:-normal}"
    ALLOWED_PATHS="${6:-}"
    # Validate priority
    case "$PRIORITY" in
      urgent|high|normal|low) ;;
      *) echo "Invalid priority: $PRIORITY (use: urgent|high|normal|low)"; exit 1 ;;
    esac
    NEXT_ID=$(jq '.nextId' "$TASKS_FILE")
    NOW=$(date -Iseconds)
    
    jq --arg agent "$AGENT" --argjson thread "$THREAD" --arg title "$TITLE" \
       --arg priority "$PRIORITY" --arg now "$NOW" --argjson id "$NEXT_ID" \
       --arg paths "$ALLOWED_PATHS" \
       '.tasks += [{id: $id, agent: $agent, thread: $thread, title: $title, 
         priority: $priority, status: "active", startedAt: $now, updatedAt: $now,
         allowedPaths: (if $paths == "" then [] else ($paths | split(",")) end)}] 
       | .nextId = ($id + 1)' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    # Priority emoji
    case "$PRIORITY" in
      urgent) P_EMOJI="🔴" ;;
      high)   P_EMOJI="🟠" ;;
      normal) P_EMOJI="🟢" ;;
      low)    P_EMOJI="⚪" ;;
    esac
    echo "Task #$NEXT_ID created: $P_EMOJI $TITLE → $AGENT (thread $THREAD) [$PRIORITY]"
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
        "#\(.id) [\(.priority // "normal")] [\(.status)] \(.title) (thread \(.thread))"' "$TASKS_FILE"
    else
      echo "=== Active Tasks (sorted by priority) ==="
      jq -r '.tasks | sort_by(if .priority == "urgent" then 0 elif .priority == "high" then 1 elif .priority == "normal" then 2 else 3 end)[] | 
        "#\(.id) \(.agent) [\(.priority // "normal")] [\(.status)] \(.title) (thread \(.thread))"' "$TASKS_FILE"
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
    ACTIVE=$(jq -r '.tasks | sort_by(if .priority == "urgent" then 0 elif .priority == "high" then 1 elif .priority == "normal" then 2 else 3 end)[] | select(.status == "active") | (if .priority == "urgent" then "🔴" elif .priority == "high" then "🟠" else "🟢" end) as $p | "\($p) #\(.id) \(.agent) — \(.title)"' "$TASKS_FILE")
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
    
  review)
    TASK_ID="$2"
    if [ -z "$TASK_ID" ]; then
      echo "Usage: task.sh review <task_id>"
      exit 1
    fi
    
    TASK=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [ -z "$TASK" ]; then
      echo "Task #$TASK_ID not found"
      exit 1
    fi
    
    AGENT=$(echo "$TASK" | jq -r '.agent')
    THREAD=$(echo "$TASK" | jq -r '.thread')
    TITLE=$(echo "$TASK" | jq -r '.title')
    NOW=$(date -Iseconds)
    
    # Determine reviewer based on agent type
    case "$AGENT" in
      koder)   REVIEWER="shomer"; REVIEWER_NAME="שומר"; REVIEW_FOCUS="אבטחה, באגים, secrets" ;;
      shomer)  REVIEWER="koder";  REVIEWER_NAME="קודר"; REVIEW_FOCUS="קוד תקין, לא שבר כלום" ;;
      tzayar)  REVIEWER="koder";  REVIEWER_NAME="קודר"; REVIEW_FOCUS="קוד תקין, responsive" ;;
      worker)  REVIEWER="koder";  REVIEWER_NAME="קודר"; REVIEW_FOCUS="קוד תקין, best practices" ;;
      *)       REVIEWER="shomer"; REVIEWER_NAME="שומר"; REVIEW_FOCUS="בדיקה כללית" ;;
    esac
    
    # Update task status
    jq --argjson id "$TASK_ID" --arg now "$NOW" --arg reviewer "$REVIEWER" \
       '(.tasks[] | select(.id == $id)).status = "in-review" |
        (.tasks[] | select(.id == $id)).reviewer = $reviewer |
        (.tasks[] | select(.id == $id)).updatedAt = $now' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    # Post review request
    "$SWARM_DIR/send.sh" "$REVIEWER" 479 "🔍 <b>Peer Review נדרש!</b>

📋 Task #$TASK_ID: $TITLE
👤 עבד: $AGENT → בודק: $REVIEWER_NAME
📍 Thread: $THREAD
🎯 מיקוד: $REVIEW_FOCUS

בדוק את העבודה ודווח:
✅ אישור: <code>task.sh approve $TASK_ID \"הערות\"</code>
❌ דחייה: <code>task.sh reject $TASK_ID \"סיבה\"</code>"
    
    echo "📋 Task #$TASK_ID sent for peer review → $REVIEWER_NAME"
    ;;
    
  approve)
    TASK_ID="$2"
    NOTES="${3:-approved}"
    NOW=$(date -Iseconds)
    
    TASK=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [ -z "$TASK" ]; then
      echo "Task #$TASK_ID not found"
      exit 1
    fi
    
    THREAD=$(echo "$TASK" | jq -r '.thread')
    AGENT=$(echo "$TASK" | jq -r '.agent')
    REVIEWER=$(echo "$TASK" | jq -r '.reviewer // "unknown"')
    
    jq --argjson id "$TASK_ID" --arg notes "$NOTES" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)).status = "approved" |
        (.tasks[] | select(.id == $id)).reviewNotes = $notes |
        (.tasks[] | select(.id == $id)).updatedAt = $now' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "✅ <b>Peer Review אושר!</b>
בודק: $REVIEWER
הערות: $NOTES
מוכן לפרודקשן! 🚀"
    
    echo "✅ Task #$TASK_ID approved by $REVIEWER"
    ;;
    
  reject)
    TASK_ID="$2"
    REASON="${3:-needs fixes}"
    NOW=$(date -Iseconds)
    
    TASK=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [ -z "$TASK" ]; then
      echo "Task #$TASK_ID not found"
      exit 1
    fi
    
    THREAD=$(echo "$TASK" | jq -r '.thread')
    AGENT=$(echo "$TASK" | jq -r '.agent')
    REVIEWER=$(echo "$TASK" | jq -r '.reviewer // "unknown"')
    
    jq --argjson id "$TASK_ID" --arg reason "$REASON" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)).status = "active" |
        (.tasks[] | select(.id == $id)).reviewNotes = $reason |
        (.tasks[] | select(.id == $id)).updatedAt = $now' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "❌ <b>Peer Review — נדרשים תיקונים</b>
בודק: $REVIEWER
סיבה: $REASON
תקן ודווח שוב."
    
    echo "❌ Task #$TASK_ID rejected: $REASON"
    ;;

  retry)
    TASK_ID="$2"
    if [ -z "$TASK_ID" ]; then
      echo "Usage: task.sh retry <task_id>"
      exit 1
    fi
    
    TASK=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [ -z "$TASK" ]; then
      echo "Task #$TASK_ID not found"
      exit 1
    fi
    
    AGENT=$(echo "$TASK" | jq -r '.agent')
    THREAD=$(echo "$TASK" | jq -r '.thread')
    TITLE=$(echo "$TASK" | jq -r '.title')
    RETRY_COUNT=$(echo "$TASK" | jq -r '.retryCount // 0')
    MAX_RETRIES=3
    NOW=$(date -Iseconds)
    
    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
      echo "🚨 Task #$TASK_ID exceeded max retries ($MAX_RETRIES). Escalating!"
      # Escalate: reassign to different agent or split
      case "$AGENT" in
        koder) NEW_AGENT="worker" ;;
        worker) NEW_AGENT="koder" ;;
        shomer) NEW_AGENT="koder" ;;
        *) NEW_AGENT="worker" ;;
      esac
      
      jq --argjson id "$TASK_ID" --arg new_agent "$NEW_AGENT" --arg now "$NOW" \
         '(.tasks[] | select(.id == $id)).agent = $new_agent |
          (.tasks[] | select(.id == $id)).status = "active" |
          (.tasks[] | select(.id == $id)).escalated = true |
          (.tasks[] | select(.id == $id)).updatedAt = $now' \
         "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
      
      "$SWARM_DIR/send.sh" "$NEW_AGENT" "$THREAD" "🚨 <b>משימה הועברה אליך (escalation)</b>
Task #$TASK_ID: $TITLE
$AGENT ניסה $RETRY_COUNT פעמים ונכשל.
נסה גישה אחרת!"
      
      echo "🔄 Escalated Task #$TASK_ID → $NEW_AGENT"
      exit 0
    fi
    
    # Determine retry strategy based on count
    NEW_RETRY=$((RETRY_COUNT + 1))
    case "$NEW_RETRY" in
      1) STRATEGY="retry — ניסיון נוסף עם אותה גישה" ;;
      2) STRATEGY="rethink — נסה גישה אחרת לגמרי" ;;
      3) STRATEGY="split — פצל את המשימה לחלקים קטנים" ;;
    esac
    
    jq --argjson id "$TASK_ID" --argjson retry "$NEW_RETRY" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)).status = "active" |
        (.tasks[] | select(.id == $id)).retryCount = $retry |
        (.tasks[] | select(.id == $id)).updatedAt = $now' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    
    "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "🔄 <b>Retry #$NEW_RETRY/$MAX_RETRIES</b>
Task #$TASK_ID: $TITLE
אסטרטגיה: $STRATEGY"
    
    echo "🔄 Task #$TASK_ID retry #$NEW_RETRY ($STRATEGY)"
    ;;
    
  history)
    jq -r '.completed | reverse | .[:20][] | 
      "#\(.id) | \(.agent) | \(.title) | thread \(.thread) | \(.completedAt // "?")"' "$TASKS_FILE"
    ;;
    
  *)
    echo "Usage: task.sh {add|done|stuck|status|list|board|history|review|approve|reject}"
    echo "  add <agent> <thread> <title> [priority]"
    echo "  done <task_id> [summary]"
    echo "  stuck <task_id> [reason]"
    echo "  status [agent]"
    echo "  list    — raw JSON"
    echo "  board   — formatted status board"
    echo "  history — completed tasks"
    ;;
esac
