#!/bin/bash
# learn.sh — Learning system for agent tasks
# Usage: learn.sh save <agent_id> <task_summary> <result:pass|fail> <lesson>
#        learn.sh query <keywords> [max_results]
#        learn.sh inject <agent_id> <task_description>
set -uo pipefail

[[ "${1:-}" == "--help" || $# -lt 1 ]] && { echo "Usage: learn.sh {save|query|inject} ..."; exit 0; }

LESSONS_FILE="$(cd "$(dirname "$0")" && pwd)/lessons.json"
[[ -f "$LESSONS_FILE" ]] || echo '[]' > "$LESSONS_FILE"

CMD="$1"; shift

case "$CMD" in
  save)
    [[ $# -lt 4 ]] && { echo "Usage: learn.sh save <agent> <task> <pass|fail> <lesson>"; exit 1; }
    AGENT="$1"; TASK="$2"; RESULT="$3"; LESSON="$4"
    ENTRY=$(jq -n --arg a "$AGENT" --arg t "$TASK" --arg r "$RESULT" --arg l "$LESSON" --arg ts "$(date -Iseconds)" \
      '{agent:$a,task:$t,result:$r,lesson:$l,timestamp:$ts}')
    jq ". += [$ENTRY]" "$LESSONS_FILE" > "${LESSONS_FILE}.tmp" && mv "${LESSONS_FILE}.tmp" "$LESSONS_FILE"
    echo "Saved lesson for $AGENT: $LESSON"
    ;;
  query)
    [[ $# -lt 1 ]] && { echo "Usage: learn.sh query <keywords> [max_results]"; exit 1; }
    KEYWORDS="$1"; MAX="${2:-5}"
    # Split keywords and grep case-insensitive
    PATTERN=$(echo "$KEYWORDS" | tr ' ' '|')
    jq -c ".[]" "$LESSONS_FILE" | grep -iE "$PATTERN" | head -n "$MAX"
    ;;
  inject)
    [[ $# -lt 2 ]] && { echo "Usage: learn.sh inject <agent_id> <task_description>"; exit 1; }
    AGENT="$1"; TASK_DESC="$2"
    # Get lessons for this agent + keyword match from task
    KEYWORDS=$(echo "$TASK_DESC" | tr ' ' '|' | head -c 200)
    RESULTS=$(jq -c ".[] | select(.agent==\"$AGENT\" or (.task | test(\"${KEYWORDS:0:50}\";\"i\") // false))" "$LESSONS_FILE" 2>/dev/null | head -5)
    [[ -z "$RESULTS" ]] && exit 0
    echo "## Lessons from past tasks:"
    echo "$RESULTS" | while read -r line; do
      LESSON=$(echo "$line" | jq -r '.lesson')
      RESULT=$(echo "$line" | jq -r '.result')
      echo "- [$RESULT] $LESSON"
    done
    ;;
  *) echo "Unknown command: $CMD"; exit 1 ;;
esac
