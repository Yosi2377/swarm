#!/bin/bash
# monitor.sh — Check for completed subagents and write done markers
# Called by heartbeat or cron. Reads /tmp/agent-done/ for existing markers
# and checks swarm logs for completion signals not yet marked.

DONE_DIR="/tmp/agent-done"
LOG_DIR="/root/.openclaw/workspace/swarm/logs"
TODAY=$(date +%Y-%m-%d)
mkdir -p "$DONE_DIR"

# Parse today's logs for completion signals
LOG_FILE="$LOG_DIR/$TODAY.jsonl"
[ ! -f "$LOG_FILE" ] && exit 0

# Look for completion messages (✅, done, הושלמה, סיימתי) in logs
grep -E '(✅|done|הושלמה|סיימתי|completed|משימה הושלמה)' "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
  AGENT=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent','unknown'))" 2>/dev/null || echo "unknown")
  TOPIC=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('thread','0'))" 2>/dev/null || echo "0")
  MSG=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message','')[:200])" 2>/dev/null || echo "")
  LABEL="${AGENT}-${TOPIC}"

  # Skip if already marked
  [ -f "$DONE_DIR/$LABEL.json" ] && continue

  echo "{\"label\":\"$LABEL\",\"topic\":\"$TOPIC\",\"agent\":\"$AGENT\",\"summary\":\"$MSG\",\"timestamp\":\"$(date -Iseconds)\",\"reported\":false}" > "$DONE_DIR/$LABEL.json"
  echo "[monitor] Marked done: $LABEL"
done
