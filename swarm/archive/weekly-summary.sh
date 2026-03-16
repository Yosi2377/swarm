#!/bin/bash
# Generate weekly summary from tasks.json
# Usage: ./weekly-summary.sh [--send]

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_FILE="$SWARM_DIR/tasks.json"
WEEK_AGO=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)

# Count completed this week
TOTAL_DONE=$(jq --arg since "$WEEK_AGO" '[.completed[] | select(.completedAt >= $since)] | length' "$TASKS_FILE")

# Tasks by agent
AGENT_STATS=$(jq -r --arg since "$WEEK_AGO" '
  [.completed[] | select(.completedAt >= $since)] | group_by(.agent) | 
  .[] | "\(.[0].agent): \(length) משימות"' "$TASKS_FILE")

# Currently active
ACTIVE=$(jq '[.tasks[] | select(.status == "active")] | length' "$TASKS_FILE")
STUCK=$(jq '[.tasks[] | select(.status == "stuck")] | length' "$TASKS_FILE")

# Build report
REPORT="📊 <b>דוח שבועי — $(date '+%d/%m/%Y')</b>

✅ <b>משימות שהושלמו:</b> $TOTAL_DONE
🔄 <b>פעילות עכשיו:</b> $ACTIVE
⚠️ <b>תקועות:</b> $STUCK

<b>📈 לפי סוכן:</b>
$AGENT_STATS"

# Add ratings if available
RATINGS_FILE="$SWARM_DIR/ratings.json"
if [ -f "$RATINGS_FILE" ]; then
  TOP_AGENT=$(jq -r 'to_entries | sort_by(.value.completed) | reverse | .[0] | "\(.key): \(.value.completed) משימות, \(.value.successRate)% הצלחה"' "$RATINGS_FILE" 2>/dev/null)
  if [ -n "$TOP_AGENT" ]; then
    REPORT+="\n\n🏆 <b>סוכן מוביל:</b> $TOP_AGENT"
  fi
fi

echo -e "$REPORT"

# Send to General if --send flag
if [ "$1" = "--send" ]; then
  "$SWARM_DIR/send.sh" or 1 "$REPORT"
fi
