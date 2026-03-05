#!/bin/bash
# agent-watcher.sh — Full pipeline: detect → notify → evaluate via hooks/agent-watcher
# Runs every minute via system crontab

DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"

OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)

for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue
  
  label=$(python3 -c "import json;print(json.load(open('$f')).get('label','unknown'))" 2>/dev/null)
  topic=$(python3 -c "import json;print(json.load(open('$f')).get('topic','4950'))" 2>/dev/null)
  summary=$(python3 -c "import json;print(json.load(open('$f')).get('summary','done'))" 2>/dev/null)
  
  # 1. Telegram notification
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${topic}" \
    -d "text=🤖 סוכן ${label} סיים: ${summary} — בודק..." > /dev/null 2>&1
  
  # 2. Use /hooks/agent-watcher (allowUnsafeExternalContent = true, deliver = true)
  #    This spawns an isolated agent that evaluates the work and delivers to Telegram
  curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
    -H "Authorization: Bearer ${HOOK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"task\": \"Agent ${label} completed: ${summary}. Evaluate the work. Run tests, check files changed, verify nothing broke. Send a detailed Hebrew report to Telegram topic ${topic} in group ${CHAT_ID} using the message tool (action=send, channel=telegram, target=${CHAT_ID}, threadId=${topic}). Include: what was done, test results, any issues found.\",
      \"sessionKey\": \"hook:watcher:${label}\",
      \"to\": \"${CHAT_ID}:${topic}\",
      \"timeoutSeconds\": 120
    }" >> /tmp/agent-watcher.log 2>&1
  
  cp "$f" "$REPORTED_DIR/$base"
  rm "$f"
  echo "$(date -Iseconds) Woke+Notified: $label → topic $topic" >> /tmp/agent-watcher.log
done
