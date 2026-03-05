#!/bin/bash
# agent-watcher.sh — Detects completed agents, notifies via Telegram + wakes OpenClaw
# Runs every minute via system crontab

DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"

OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
GATEWAY_PORT=18789
HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)

for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue
  
  label=$(python3 -c "import json;print(json.load(open('$f')).get('label','unknown'))" 2>/dev/null)
  topic=$(python3 -c "import json;print(json.load(open('$f')).get('topic','4950'))" 2>/dev/null)
  summary=$(python3 -c "import json;print(json.load(open('$f')).get('summary','done'))" 2>/dev/null)
  
  # 1. Send Telegram notification (user sees it immediately)
  MSG="🤖 סוכן ${label} סיים: ${summary}"
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${topic}" \
    -d "text=${MSG}" > /dev/null 2>&1
  
  # 2. Wake OpenClaw via hooks API (triggers a turn in the topic session)
  SESSION_KEY="agent:main:telegram:group:${CHAT_ID}:topic:${topic}"
  curl -s -X POST "http://localhost:${GATEWAY_PORT}/hooks/agent" \
    -H "Authorization: Bearer ${HOOK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"[System] Agent ${label} completed: ${summary}. Evaluate the results and report to Yossi.\",\"sessionKey\":\"${SESSION_KEY}\"}" > /dev/null 2>&1
  
  # 3. Move to reported
  cp "$f" "$REPORTED_DIR/$base"
  rm "$f"
  
  echo "$(date -Iseconds) Woke: $label → topic $topic"
done
