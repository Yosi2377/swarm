#!/bin/bash
# watchdog.sh — Pure bash monitoring. NO AI tokens. Runs via systemd timer.
# Only sends alerts when something is WRONG.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$SCRIPT_DIR/send.sh"
ALERT=0

# 1. Services alive?
for SVC in betting-backend betting-aggregator; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    systemctl restart "$SVC" 2>/dev/null
    sleep 3
    if systemctl is-active --quiet "$SVC"; then
      "$SEND" or 1 "⚠️ $SVC was down — auto-restarted ✅" 2>/dev/null
    else
      "$SEND" or 1 "🔴 $SVC DOWN — restart failed!" 2>/dev/null
    fi
    ALERT=1
  fi
done

# 2. HTTP check
for URL in "http://95.111.247.22:8089|Production" "http://95.111.247.22:9089|Sandbox"; do
  ADDR="${URL%%|*}"
  NAME="${URL##*|}"
  HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$ADDR" 2>/dev/null)
  if [ "$HTTP" != "200" ]; then
    "$SEND" or 1 "🔴 $NAME HTTP $HTTP (expected 200)" 2>/dev/null
    ALERT=1
  fi
done

# 3. Disk space
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$DISK_PCT" -gt 85 ]; then
  "$SEND" or 1 "⚠️ Disk ${DISK_PCT}% — cleanup needed" 2>/dev/null
  # Auto-clean
  journalctl --vacuum-time=3d 2>/dev/null
  ALERT=1
fi

# 4. MongoDB alive
if ! mongosh --quiet --eval "db.runCommand({ping:1})" betting >/dev/null 2>&1; then
  "$SEND" or 1 "🔴 MongoDB not responding!" 2>/dev/null
  ALERT=1
fi

# 5. Pipeline completions (supervisor role)
if [ -f /tmp/pipeline-completed.jsonl ] && [ -f /tmp/supervisor-reported.txt ]; then
  while IFS= read -r LINE; do
    TASK=$(echo "$LINE" | python3 -c "import json,sys;print(json.loads(sys.stdin.read())['task'])" 2>/dev/null)
    if [ -n "$TASK" ] && ! grep -q "task-$TASK" /tmp/supervisor-reported.txt 2>/dev/null; then
      DESC=$(echo "$LINE" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('desc','?'))" 2>/dev/null)
      AGENT=$(echo "$LINE" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('agent','?'))" 2>/dev/null)
      PASS=$(echo "$LINE" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('pass','?'))" 2>/dev/null)
      "$SEND" or 1 "✅ Task $TASK ($AGENT): $DESC — $PASS/8" 2>/dev/null
      echo "task-$TASK" >> /tmp/supervisor-reported.txt
    fi
  done < /tmp/pipeline-completed.jsonl
elif [ -f /tmp/pipeline-completed.jsonl ]; then
  touch /tmp/supervisor-reported.txt
fi

# Silent if no issues
exit 0
