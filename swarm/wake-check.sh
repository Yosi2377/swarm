#!/bin/bash
# Check for completed agents and notify via Telegram directly
DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"

# Check for new done markers
for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue
  
  # Read the marker
  label=$(cat "$f" | python3 -c "import json,sys;print(json.load(sys.stdin).get('label','unknown'))" 2>/dev/null)
  summary=$(cat "$f" | python3 -c "import json,sys;print(json.load(sys.stdin).get('summary','done'))" 2>/dev/null)
  
  # Send to General topic via Or bot
  TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token)
  curl -s "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=-1003815143703" \
    -d "message_thread_id=1" \
    -d "text=🤖 סוכן סיים: ${label} — ${summary}" > /dev/null
  
  # Mark as reported
  mv "$f" "$REPORTED_DIR/"
done
