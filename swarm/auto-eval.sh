#!/bin/bash
# auto-eval.sh — Background auto-evaluation after agent spawn
# Usage: nohup bash auto-eval.sh <label> <topic> <summary> <eval_instructions> &
#
# Call this RIGHT AFTER sessions_spawn with nohup.
# It waits, then triggers /hooks/agent-watcher to evaluate and report.

LABEL="${1:?Usage: auto-eval.sh <label> <topic> <summary> <eval_instructions>}"
TOPIC="${2:-4950}"
SUMMARY="${3:-Agent completed}"
EVAL="${4:-Run tests and check the work}"
WAIT="${5:-90}"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"

# Wait for agent to finish
sleep "$WAIT"

# Telegram notification
curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
  -d "text=🤖 סוכן ${LABEL} סיים. מפעיל הערכה אוטומטית..." > /dev/null 2>&1

# Trigger hook evaluation
curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
  -H "Authorization: Bearer ${HOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"task\": \"Agent ${LABEL} completed: ${SUMMARY}. ${EVAL}. Send Hebrew report to Telegram using message tool: action=send, channel=telegram, target=${CHAT_ID}, threadId=${TOPIC}. Include: what was done, test results, issues found.\",
    \"sessionKey\": \"hook:eval:${LABEL}-$(date +%s)\"
  }" > /dev/null 2>&1

echo "$(date -Iseconds) auto-eval triggered: ${LABEL} → topic ${TOPIC}" >> /tmp/agent-watcher.log
