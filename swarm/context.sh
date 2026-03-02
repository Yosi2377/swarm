#!/bin/bash
# context.sh — Update shared active context
# Usage:
#   context.sh update <agent_emoji> <agent_name> <status> <task> <thread>
#   context.sh idle <agent_emoji> <agent_name>
#   context.sh show
#
# Example:
#   context.sh update "⚙️" "קודר" "working" "Fix login bug" "4950"
#   context.sh idle "⚙️" "קודר"
#   context.sh show

DIR="$(cd "$(dirname "$0")" && pwd)"
CONTEXT_FILE="$DIR/memory/shared/active-context.md"
ACTION="$1"

mkdir -p "$DIR/memory/shared"

# Ensure file exists with header
if [ ! -f "$CONTEXT_FILE" ]; then
  cat > "$CONTEXT_FILE" <<'EOF'
# 🔄 Active Context — מצב נוכחי של כל הסוכנים

> **כל סוכן חייב לעדכן כשמתחיל/מסיים משימה!**

## סוכנים פעילים

| סוכן | סטטוס | משימה | Thread | עדכון אחרון |
|-------|--------|-------|--------|-------------|
| 🐝 אור | idle | — | — | — |
| ⚙️ קודר | idle | — | — | — |
| 🔒 שומר | idle | — | — | — |
| 🎨 צייר | idle | — | — | — |
| 🤖 עובד | idle | — | — | — |
| 🔍 חוקר | idle | — | — | — |
| 🧪 בודק | idle | — | — | — |

## הערות חשובות

## שיתופי פעולה פעילים
EOF
fi

NOW=$(date '+%Y-%m-%d %H:%M')

case "$ACTION" in
  update)
    EMOJI="$2"
    NAME="$3"
    STATUS="${4:-working}"
    TASK="${5:-—}"
    THREAD="${6:-—}"
    
    # Use python for reliable unicode table row replacement
    python3 -c "
import sys
name = sys.argv[1]
new_line = '| {emoji} {name} | {status} | {task} | {thread} | {now} |'.format(
    emoji=sys.argv[2], name=name, status=sys.argv[3], task=sys.argv[4], thread=sys.argv[5], now=sys.argv[6])
with open(sys.argv[7], 'r') as f:
    lines = f.readlines()
out = []
for line in lines:
    if name in line and '|' in line and 'סוכן' not in line and '---' not in line:
        out.append(new_line + '\n')
    else:
        out.append(line)
with open(sys.argv[7], 'w') as f:
    f.writelines(out)
" "$NAME" "$EMOJI" "$STATUS" "$TASK" "$THREAD" "$NOW" "$CONTEXT_FILE"
    
    echo "✅ Context updated: ${EMOJI} ${NAME} → ${STATUS} (${TASK})"
    ;;
    
  idle)
    EMOJI="$2"
    NAME="$3"
    
    python3 -c "
import sys
name = sys.argv[1]
new_line = '| {emoji} {name} | idle | — | — | {now} |'.format(
    emoji=sys.argv[2], name=name, now=sys.argv[3])
with open(sys.argv[4], 'r') as f:
    lines = f.readlines()
out = []
for line in lines:
    if name in line and '|' in line and 'סוכן' not in line and '---' not in line:
        out.append(new_line + '\n')
    else:
        out.append(line)
with open(sys.argv[4], 'w') as f:
    f.writelines(out)
" "$NAME" "$EMOJI" "$NOW" "$CONTEXT_FILE"
    
    echo "✅ Context updated: ${EMOJI} ${NAME} → idle"
    ;;
    
  show)
    cat "$CONTEXT_FILE"
    ;;
    
  *)
    echo "Usage: context.sh <update|idle|show> [args...]"
    exit 1
    ;;
esac
