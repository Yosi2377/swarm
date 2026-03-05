#!/bin/bash
# agent-watcher.sh — Full pipeline: detect → notify → wake Or via hooks
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
    -d "text=🤖 סוכן ${label} סיים: ${summary} — אור בודק..." > /dev/null 2>&1
  
  # 2. Wake Or via hooks API to the TOPIC session (works when session is free)
  SESSION_KEY="agent:main:telegram:group:${CHAT_ID}:topic:${topic}"
  curl -s -X POST "http://localhost:18789/hooks/agent" \
    -H "Authorization: Bearer ${HOOK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"[System] Agent ${label} completed: ${summary}. IMPORTANT: You must now evaluate the agent work. Run tests, check the server, open browser if needed. Send your evaluation report to Yossi in this topic. Be thorough — check for side effects the agent might have caused.\",\"sessionKey\":\"${SESSION_KEY}\"}" > /dev/null 2>&1
  
  # 3. ALSO try General topic as backup (in case topic session is busy)
  curl -s -X POST "http://localhost:18789/hooks/agent" \
    -H "Authorization: Bearer ${HOOK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"Agent ${label} completed in topic ${topic}: ${summary}. Evaluate the work and send detailed report to topic ${topic} using message tool (action=send, channel=telegram, target=${CHAT_ID}, threadId=${topic}).\",\"sessionKey\":\"agent:main:telegram:group:${CHAT_ID}:topic:1\"}" > /dev/null 2>&1
  
  cp "$f" "$REPORTED_DIR/$base"
  rm "$f"
  echo "$(date -Iseconds) Woke+Notified: $label → topic $topic"
done
