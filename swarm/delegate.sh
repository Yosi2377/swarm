#!/bin/bash
# delegate.sh — Full delegation wrapper with structured task schema + auto-lessons
# Usage: delegate.sh <agent> <task_description> [project_keywords] [thread_id] [priority]
# 
# What it does:
#   1. Creates structured task JSON (if thread_id provided)
#   2. Queries relevant lessons from learning system
#   3. Queries relevant skills from swarm/skills/
#   4. Updates shared active context
#   5. Outputs a COMPLETE task prompt ready for sessions_spawn
#
# Example:
#   PROMPT=$(swarm/delegate.sh koder "Fix basketball spreads" "basketball spread" 4950 high)

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="$1"
TASK="$2"
KEYWORDS="${3:-$2}"
THREAD="${4:-}"
PRIORITY="${5:-normal}"

if [ -z "$AGENT" ] || [ -z "$TASK" ]; then
  echo "Usage: delegate.sh <agent> <task_description> [keywords] [thread_id] [priority]"
  exit 1
fi

# 0. Agent emoji mapping
case "$AGENT" in
  koder)      EMOJI="⚙️"; NAME="קודר" ;;
  shomer)     EMOJI="🔒"; NAME="שומר" ;;
  tzayar)     EMOJI="🎨"; NAME="צייר" ;;
  researcher) EMOJI="🔍"; NAME="חוקר" ;;
  worker)     EMOJI="🤖"; NAME="עובד" ;;
  bodek)      EMOJI="🧪"; NAME="בודק" ;;
  *)          EMOJI="🤖"; NAME="$AGENT" ;;
esac

# 1. Create structured task JSON (if thread provided)
TASK_JSON_INFO=""
if [ -n "$THREAD" ]; then
  bash "$DIR/create-task.sh" "$AGENT" "$THREAD" "$TASK" "$TASK" "$PRIORITY" "" "" "" "or" 2>/dev/null
  TASK_JSON_INFO="
📋 Task file: swarm/tasks/${THREAD}.json + swarm/tasks/${THREAD}.md
עדכן progress ב-task file בכל שלב."
fi

# 2. Update shared active context
if [ -n "$THREAD" ]; then
  bash "$DIR/context.sh" update "$EMOJI" "$NAME" "assigned" "$TASK" "$THREAD" 2>/dev/null
fi

# 3. Get relevant lessons
LESSONS=$(bash "$DIR/inject-lessons.sh" "$KEYWORDS" 2>/dev/null)

# 4. Get relevant skill file content (if exists)
SKILL_FILE=""
for f in "$DIR/skills/"*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  for kw in $KEYWORDS; do
    if echo "$BASENAME" | grep -qi "$kw"; then
      SKILL_FILE="$f"
      break 2
    fi
  done
done

SKILL_CONTENT=""
if [ -n "$SKILL_FILE" ]; then
  SKILL_CONTENT="

📖 Relevant skill knowledge ($(basename "$SKILL_FILE")):
$(head -100 "$SKILL_FILE")"
fi

# 5. Build the complete prompt
cat <<PROMPT
$TASK

קרא את swarm/SYSTEM.md. אתה $AGENT ($EMOJI).
${TASK_JSON_INFO}

$LESSONS
$SKILL_CONTENT

⛔ כללים:
- עבוד ב-sandbox בלבד
- אל תעשה deploy לפרודקשן
- צלם screenshot של התוצאה
- דווח כשסיימת

🚨 חובה — עדכון context:
  bash /root/.openclaw/workspace/swarm/context.sh update "$EMOJI" "$NAME" "working" "תיאור קצר" "${THREAD:-THREAD_ID}"

🚨 חובה — הפקודה הראשונה:
  /root/.openclaw/workspace/swarm/notify.sh ${THREAD:-THREAD_ID} progress "מתחיל: תיאור קצר"

🚨 חובה — בסיום:
  /root/.openclaw/workspace/swarm/notify.sh ${THREAD:-THREAD_ID} success "✅ הושלם: תיאור"
  bash /root/.openclaw/workspace/swarm/context.sh idle "$EMOJI" "$NAME"
  bash /root/.openclaw/workspace/swarm/learn.sh score $AGENT success "תיאור קצר"
  # peer review יופעל אוטומטית ע"י notify watcher

⛔ אם לא שלחת notify — המשימה לא נחשבת כסיימת!
PROMPT
