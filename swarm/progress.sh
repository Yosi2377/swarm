#!/bin/bash
# progress.sh — Auto-report every 3 minutes
# Usage: swarm/progress.sh <agent_id> <thread_id> "task description" &
# Kill with: kill $PROGRESS_PID

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="${1:?Usage: progress.sh <agent_id> <thread_id> <description>}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:-עבודה}"
INTERVAL=180  # 3 minutes
NO_CHANGE_COUNT=0
LAST_DIFF=""

send() {
  "$SWARM_DIR/send.sh" "$AGENT_ID" "$THREAD_ID" "$1"
}

send "🔄 <b>מוניטור הופעל</b> — דיווח כל 3 דקות
📋 משימה: $TASK_DESC"

while true; do
  sleep "$INTERVAL"

  # Git diff stat from workspace
  DIFF=$(cd /root/.openclaw/workspace && git diff --stat 2>/dev/null | tail -5)
  STATUS=$(cd /root/.openclaw/workspace && git status --short 2>/dev/null | head -10)
  
  # Check sandbox too
  SANDBOX_DIFF=""
  if [ -d /root/sandbox ]; then
    SANDBOX_DIFF=$(cd /root/sandbox && find . -name '*.md' -o -name '*.sh' -o -name '*.js' -o -name '*.json' -newer /tmp/progress-marker 2>/dev/null | head -10)
  fi
  touch /tmp/progress-marker

  # Count changed files
  CHANGED=$(echo "$STATUS" | grep -c '.')
  
  # Build message
  MSG="📊 <b>דיווח אוטומטי</b> ($(date +%H:%M))
📋 $TASK_DESC
"

  if [ -n "$DIFF" ]; then
    MSG="$MSG
<pre>$DIFF</pre>"
    NO_CHANGE_COUNT=0
  elif [ "$CHANGED" -gt 0 ]; then
    MSG="$MSG
📝 $CHANGED קבצים שונו
<pre>$(echo "$STATUS" | head -5)</pre>"
    NO_CHANGE_COUNT=0
  else
    NO_CHANGE_COUNT=$((NO_CHANGE_COUNT + 1))
    MSG="$MSG
⚠️ אין שינויים ($((NO_CHANGE_COUNT * 3)) דקות)"
  fi

  if [ -n "$SANDBOX_DIFF" ]; then
    MSG="$MSG
🏗️ sandbox: $(echo "$SANDBOX_DIFF" | wc -l) קבצים עודכנו"
  fi

  send "$MSG"

  # Alert if stuck for 6+ minutes (2 cycles)
  if [ "$NO_CHANGE_COUNT" -ge 2 ]; then
    "$SWARM_DIR/send.sh" or 1 "⚠️ <b>התראה:</b> סוכן <code>$AGENT_ID</code> ב-#$THREAD_ID ללא שינויים ${NO_CHANGE_COUNT}*3 דקות!
📋 $TASK_DESC"
  fi
done
