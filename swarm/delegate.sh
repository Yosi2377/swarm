#!/bin/bash
# delegate.sh — Full delegation wrapper with auto-lessons + auto-score
# Usage: delegate.sh <agent> <task_description> [project_keywords]
# 
# What it does:
#   1. Queries relevant lessons from learning system
#   2. Queries relevant skills from swarm/skills/
#   3. Outputs a COMPLETE task prompt ready for sessions_spawn
#
# Example:
#   PROMPT=$(swarm/delegate.sh koder "Fix basketball spreads" "basketball spread inplay")
#   Then use $PROMPT in sessions_spawn task parameter

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="$1"
TASK="$2"
KEYWORDS="${3:-$2}"

if [ -z "$AGENT" ] || [ -z "$TASK" ]; then
  echo "Usage: delegate.sh <agent> <task_description> [keywords]"
  exit 1
fi

# 1. Get relevant lessons
LESSONS=$(bash "$DIR/inject-lessons.sh" "$KEYWORDS" 2>/dev/null)

# 2. Get relevant skill file content (if exists)
SKILL_FILE=""
for f in "$DIR/skills/"*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  # Check if any keyword matches the skill filename
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

# 3. Build the complete prompt
cat <<PROMPT
$TASK

קרא את swarm/SYSTEM.md. אתה $AGENT.

$LESSONS
$SKILL_CONTENT

⛔ כללים:
- עבוד ב-sandbox בלבד
- אל תעשה deploy לפרודקשן
- צלם screenshot של התוצאה
- דווח כשסיימת

📋 בסיום המשימה, הרץ:
  bash /root/.openclaw/workspace/swarm/learn.sh score $AGENT success "תיאור קצר של מה שעשית"
  (או fail אם נכשלת)
PROMPT
