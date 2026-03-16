#!/bin/bash
# Update agent rating after task completion
# Usage: ./rate.sh <agent> <task_id> <success|rollback> [minutes]

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
RATINGS_FILE="$SWARM_DIR/ratings.json"
AGENT="$1"
TASK_ID="$2"
RESULT="$3"
MINUTES="${4:-0}"

if [ -z "$AGENT" ] || [ -z "$TASK_ID" ] || [ -z "$RESULT" ]; then
  echo "Usage: $0 <agent> <task_id> <success|rollback> [minutes]"
  exit 1
fi

if [ "$RESULT" = "success" ]; then
  jq --arg a "$AGENT" --argjson m "$MINUTES" --argjson tid "$TASK_ID" \
    '.[$a].completed += 1 | .[$a].totalMinutes += $m | 
     .[$a].tasks += [{id: $tid, result: "success", minutes: $m}] |
     .[$a].successRate = ((.[$a].completed * 100) / ((.[$a].completed + .[$a].rollbacks) | if . == 0 then 1 else . end) | floor)' \
    "$RATINGS_FILE" > "$RATINGS_FILE.tmp" && mv "$RATINGS_FILE.tmp" "$RATINGS_FILE"
  echo "✅ $AGENT rated: success (task #$TASK_ID)"
elif [ "$RESULT" = "rollback" ]; then
  jq --arg a "$AGENT" --argjson tid "$TASK_ID" \
    '.[$a].rollbacks += 1 | 
     .[$a].tasks += [{id: $tid, result: "rollback"}] |
     .[$a].successRate = ((.[$a].completed * 100) / ((.[$a].completed + .[$a].rollbacks) | if . == 0 then 1 else . end) | floor)' \
    "$RATINGS_FILE" > "$RATINGS_FILE.tmp" && mv "$RATINGS_FILE.tmp" "$RATINGS_FILE"
  echo "❌ $AGENT rated: rollback (task #$TASK_ID)"
fi
