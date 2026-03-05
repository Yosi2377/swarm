#!/bin/bash
# agent-watcher.sh — Monitors completed agents, sends Telegram notification + wakes OpenClaw
# Runs every minute via system crontab

DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"

OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
DEFAULT_TOPIC="4950"

# Gateway API for waking OpenClaw session
GATEWAY_PORT=18789
GATEWAY_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('gateway',{}).get('auth',{}).get('token',''))" 2>/dev/null)

send_telegram() {
  local topic="$1"
  local msg="$2"
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${topic}" \
    -d "text=${msg}" > /dev/null 2>&1
}

wake_openclaw() {
  local topic="$1"
  local text="$2"
  local session_key="agent:main:telegram:group:${CHAT_ID}:topic:${topic}"
  curl -s -X POST "http://localhost:${GATEWAY_PORT}/tools/invoke" \
    -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tool\":\"cron\",\"args\":{\"action\":\"wake\",\"text\":\"${text}\",\"mode\":\"now\"},\"sessionKey\":\"${session_key}\"}" > /dev/null 2>&1
}

found=0
for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue
  
  found=1
  label=$(python3 -c "import json;print(json.load(open('$f')).get('label','unknown'))" 2>/dev/null)
  topic=$(python3 -c "import json;print(json.load(open('$f')).get('topic','$DEFAULT_TOPIC'))" 2>/dev/null)
  summary=$(python3 -c "import json;print(json.load(open('$f')).get('summary','done'))" 2>/dev/null)
  
  MSG="🤖 סוכן ${label} סיים: ${summary}"
  
  # 1. Send Telegram notification (visible to user)
  send_telegram "$topic" "$MSG"
  
  # 2. Wake OpenClaw session (makes Or auto-respond)
  wake_openclaw "$topic" "Agent ${label} completed: ${summary}. Check results and report to Yossi."
  
  # 3. Move to reported
  cp "$f" "$REPORTED_DIR/$base"
  rm "$f"
  
  echo "$(date -Iseconds) Reported + Woke: $label → topic $topic"
done
