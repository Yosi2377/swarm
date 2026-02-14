#!/bin/bash
# delegate.sh — Agent-to-agent delegation
# Usage: delegate.sh <from_agent> <to_agent> <parent_thread> "task description"
# Creates a sub-topic, posts task, and writes activation request to /tmp/delegate-queue/

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
FROM_AGENT="$1"
TO_AGENT="$2"
PARENT_THREAD="$3"
TASK="$4"

if [ -z "$FROM_AGENT" ] || [ -z "$TO_AGENT" ] || [ -z "$PARENT_THREAD" ] || [ -z "$TASK" ]; then
  echo "Usage: delegate.sh <from_agent> <to_agent> <parent_thread> \"task description\""
  exit 1
fi

# Agent emoji map
declare -A EMOJI=(
  [or]="🐝" [shomer]="🔒" [koder]="⚙️" [tzayar]="🎨" [worker]="🤖" [researcher]="🔍"
)
declare -A NAMES=(
  [or]="אור" [shomer]="שומר" [koder]="קודר" [tzayar]="צייר" [worker]="עובד" [researcher]="חוקר"
)

FROM_EMOJI="${EMOJI[$FROM_AGENT]:-🤖}"
TO_EMOJI="${EMOJI[$TO_AGENT]:-🤖}"
TO_NAME="${NAMES[$TO_AGENT]:-$TO_AGENT}"

# Create sub-topic
OR_TOKEN=$(cat "$SWARM_DIR/.or-token" 2>/dev/null)
TOPIC_NAME="${TO_EMOJI} ${TASK:0:60}"
RESULT=$(curl -s "https://api.telegram.org/bot${OR_TOKEN}/createForumTopic" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\": -1003815143703, \"name\": \"${TOPIC_NAME}\"}")

THREAD_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['message_thread_id'])" 2>/dev/null)

if [ -z "$THREAD_ID" ]; then
  echo "ERROR: Failed to create topic"
  echo "$RESULT"
  exit 1
fi

# Post task as the target agent
"$SWARM_DIR/send.sh" "$TO_AGENT" "$THREAD_ID" "${TO_EMOJI} משימה מ-${FROM_EMOJI} ${NAMES[$FROM_AGENT]:-$FROM_AGENT}:

${TASK}

📋 parent thread: ${PARENT_THREAD}
דווח: send.sh ${TO_AGENT} ${THREAD_ID} \"message\"
בסיום דווח גם ל-parent: send.sh ${FROM_AGENT} ${PARENT_THREAD} \"${TO_EMOJI}→${FROM_EMOJI} סיימתי: ...\""

# Write activation request
mkdir -p /tmp/delegate-queue
ACTIVATION_FILE="/tmp/delegate-queue/${THREAD_ID}.json"
cat > "$ACTIVATION_FILE" << EOF
{
  "threadId": $THREAD_ID,
  "fromAgent": "$FROM_AGENT",
  "toAgent": "$TO_AGENT",
  "parentThread": $PARENT_THREAD,
  "task": $(python3 -c "import json; print(json.dumps('$TASK'))"),
  "timestamp": "$(date -Iseconds)",
  "status": "pending"
}
EOF

echo "✅ Delegated to ${TO_NAME} (${TO_EMOJI})"
echo "THREAD_ID=$THREAD_ID"
echo "ACTIVATION=$ACTIVATION_FILE"
