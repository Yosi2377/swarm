#!/bin/bash
# check-done-agents.sh — Polls OpenClaw for completed sub-agents, triggers evaluation
# Runs every minute via crontab. No markers needed - checks API directly.

STATE_FILE="/tmp/evaluated-agents.txt"
touch "$STATE_FILE"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
GW_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('gateway',{}).get('auth',{}).get('token',''))" 2>/dev/null)
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"

# Get recent completed sub-agents from OpenClaw API
RESULT=$(curl -s "http://localhost:18789/gateway/sessions" \
  -H "Authorization: Bearer ${GW_TOKEN}" 2>/dev/null)

# Parse sessions for completed sub-agents with labels
echo "$RESULT" | python3 -c "
import json, sys, os

try:
    data = json.load(sys.stdin)
except:
    sys.exit(0)

sessions = data if isinstance(data, dict) else {}
state_file = '/tmp/evaluated-agents.txt'
evaluated = set()
if os.path.exists(state_file):
    with open(state_file) as f:
        evaluated = set(f.read().strip().split('\n'))

for key, val in sessions.items():
    if 'subagent' not in key:
        continue
    sid = val.get('sessionId', '')
    if sid in evaluated or not sid:
        continue
    # This is a completed sub-agent we haven't evaluated yet
    label = val.get('label', key.split(':')[-1][:20])
    topic = val.get('topic', '4950')
    print(f'{sid}|{label}|{topic}')
" 2>/dev/null | while IFS='|' read -r sid label topic; do
    [ -z "$sid" ] && continue
    
    # Mark as evaluated
    echo "$sid" >> "$STATE_FILE"
    
    # Send Telegram notification
    curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
      -d "chat_id=${CHAT_ID}" -d "message_thread_id=${topic}" \
      -d "text=🤖 סוכן ${label} סיים. מפעיל הערכה..." > /dev/null 2>&1
    
    # Trigger evaluation
    curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
      -H "Authorization: Bearer ${HOOK_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"task\": \"Sub-agent ${label} just completed. Check recent work in the project directory. Run tests if available. Send Hebrew report to Telegram using message tool: action=send, channel=telegram, target=${CHAT_ID}, threadId=${topic}.\",
        \"sessionKey\": \"hook:eval:${sid}\"
      }" > /dev/null 2>&1
    
    echo "$(date -Iseconds) Eval triggered: ${label}" >> /tmp/agent-watcher.log
done
