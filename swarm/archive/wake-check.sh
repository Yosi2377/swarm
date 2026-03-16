#!/bin/bash
# wake-check.sh — Check for completed agents and notify via Telegram
# Runs every 2 minutes via system crontab
# Sends to BOTH General (topic 1) AND the task's topic to wake the orchestrator

DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"

OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"

for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue

  label=$(python3 -c "import json;print(json.load(open('$f')).get('label','unknown'))" 2>/dev/null)
  topic=$(python3 -c "import json;print(json.load(open('$f')).get('topic','1'))" 2>/dev/null)
  summary=$(python3 -c "import json;print(json.load(open('$f')).get('summary','done'))" 2>/dev/null)

  MSG="🤖 סוכן סיים: ${label} — ${summary}"

  # Send to General (topic 1) — this wakes the main orchestrator session
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=1" \
    -d "text=${MSG}" > /dev/null 2>&1

  # ALSO send to the task's topic — this wakes the topic-specific session
  if [ "$topic" != "1" ] && [ -n "$topic" ]; then
    curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
      -d "chat_id=${CHAT_ID}" -d "message_thread_id=${topic}" \
      -d "text=${MSG}" > /dev/null 2>&1
  fi

  mv "$f" "$REPORTED_DIR/"
  echo "$(date -Iseconds) Reported: $label (topic $topic)"
done
