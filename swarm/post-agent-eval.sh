#!/bin/bash
# post-agent-eval.sh — Called AFTER sessions_spawn to trigger auto-evaluation
# Usage: post-agent-eval.sh <label> <topic> <summary> <eval_instructions>
# Waits for agent to finish, then calls /hooks/agent-watcher to evaluate

LABEL="${1:?Usage: post-agent-eval.sh <label> <topic> <summary> <eval_instructions>}"
TOPIC="${2:-4950}"
SUMMARY="${3:-Agent completed}"
EVAL="${4:-Run tests and check the work}"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
CHAT_ID="-1003815143703"
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)

# Wait for agent to finish (check every 10 sec, max 5 min)
for i in $(seq 1 30); do
  sleep 10
done

# Agent should be done by now (most tasks < 2 min)
# Send Telegram notification
curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
  -d "text=🤖 סוכן ${LABEL} סיים. מפעיל הערכה אוטומטית..." > /dev/null 2>&1

# Trigger evaluation via hooks/agent-watcher
curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
  -H "Authorization: Bearer ${HOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"task\": \"Agent ${LABEL} completed: ${SUMMARY}. ${EVAL}. Send a Hebrew report to Telegram using message tool: action=send, channel=telegram, target=${CHAT_ID}, threadId=${TOPIC}. Include test results, what changed, any issues.\",
    \"sessionKey\": \"hook:eval:${LABEL}\"
  }" > /dev/null 2>&1

echo "$(date) eval triggered for ${LABEL}" >> /tmp/agent-watcher.log
