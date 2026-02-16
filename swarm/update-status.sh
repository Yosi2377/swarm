#!/bin/bash
# Usage: update-status.sh <agent> <task_id> <status> [description]
# status: working|done|blocked|idle
# agent: shomer|koder|tzayar|researcher|worker|bodek

AGENT="$1"
TASK_ID="$2"
STATUS="$3"
DESC="${4:-}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
STATUS_FILE="/root/.openclaw/workspace/swarm/status.md"

if [ -z "$AGENT" ] || [ -z "$STATUS" ]; then
  echo "Usage: update-status.sh <agent> <task_id> <status> [description]"
  echo "  agent: shomer|koder|tzayar|researcher|worker|bodek"
  echo "  status: working|done|blocked|idle"
  exit 1
fi

# Map agent to emoji
declare -A EMOJI_MAP=(
  [shomer]="🔒 שומר"
  [koder]="⚙️ קודר"
  [tzayar]="🎨 צייר"
  [researcher]="🔍 חוקר"
  [worker]="🤖 עובד"
  [bodek]="🧪 בודק"
)

AGENT_DISPLAY="${EMOJI_MAP[$AGENT]:-$AGENT}"

# Update timestamp
sed -i "s/^Updated: .*/Updated: $TIMESTAMP/" "$STATUS_FILE"

# Update Agent Status table
case "$STATUS" in
  working)
    sed -i "s/| ${AGENT_DISPLAY} |.*|/| ${AGENT_DISPLAY} | ⏳ working | ${TASK_ID}: ${DESC} | ${TIMESTAMP} |/" "$STATUS_FILE"
    ;;
  done)
    sed -i "s/| ${AGENT_DISPLAY} |.*|/| ${AGENT_DISPLAY} | idle | — | ${TIMESTAMP} |/" "$STATUS_FILE"
    # Move task to Recent Completions (append before last empty line of that table)
    # Add to Active Tasks cleanup - remove task row if exists
    sed -i "/| .* | ${TASK_ID} | ${AGENT_DISPLAY} |/d" "$STATUS_FILE"
    # Add to Recent Completions
    sed -i "/^## Recent Completions/,/^$/{
      /^|---/a | ${DESC:-task} | ${TASK_ID} | ✅ Done | ${TIMESTAMP} |
    }" "$STATUS_FILE"
    ;;
  blocked)
    sed -i "s/| ${AGENT_DISPLAY} |.*|/| ${AGENT_DISPLAY} | ❌ blocked | ${TASK_ID}: ${DESC} | ${TIMESTAMP} |/" "$STATUS_FILE"
    ;;
  idle)
    sed -i "s/| ${AGENT_DISPLAY} |.*|/| ${AGENT_DISPLAY} | idle | — | ${TIMESTAMP} |/" "$STATUS_FILE"
    ;;
esac

# Update/add Active Tasks entry for non-idle/done
if [ "$STATUS" = "working" ] || [ "$STATUS" = "blocked" ]; then
  # Check if task already in Active Tasks
  if grep -q "| .* | ${TASK_ID} |" "$STATUS_FILE"; then
    # Update existing
    STATUS_ICON="⏳"
    [ "$STATUS" = "blocked" ] && STATUS_ICON="❌"
    sed -i "s/| .* | ${TASK_ID} | .* | .* | .* | .* |/| ${DESC:-task} | ${TASK_ID} | ${AGENT_DISPLAY} | ${STATUS_ICON} ${STATUS} | — | ${TIMESTAMP} |/" "$STATUS_FILE"
  else
    # Add new row to Active Tasks
    STATUS_ICON="⏳"
    [ "$STATUS" = "blocked" ] && STATUS_ICON="❌"
    sed -i "/^## Active Tasks/,/^$/{
      /^|---/a | ${DESC:-task} | ${TASK_ID} | ${AGENT_DISPLAY} | ${STATUS_ICON} ${STATUS} | ${TIMESTAMP} | ${TIMESTAMP} |
    }" "$STATUS_FILE"
  fi
fi

# Git commit
cd /root/.openclaw/workspace && git add swarm/status.md && git commit -m "status: ${AGENT} ${STATUS} ${TASK_ID}" --allow-empty -q 2>/dev/null

echo "✅ Status updated: ${AGENT} → ${STATUS} (task: ${TASK_ID})"
