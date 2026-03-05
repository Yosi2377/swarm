#!/bin/bash
# eval-and-retry.sh — Evaluate agent work. If FAIL, retry once.
# Called by smart-eval.sh via hooks/agent-watcher
# Usage: eval-and-retry.sh <label> <topic> <eval_cmd> <retry_task>
#
# The hooks/agent-watcher does the eval. This script checks the RESULT
# and triggers retry if needed.

LABEL="${1:?}"
TOPIC="${2:-4950}"
EVAL_CMD="${3:-npm test}"
RETRY_TASK="${4:-}"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
RETRY_FILE="/tmp/retry-${LABEL}.count"

# Check retry count
RETRIES=0
[ -f "$RETRY_FILE" ] && RETRIES=$(cat "$RETRY_FILE")

if [ "$RETRIES" -ge 2 ]; then
  # Max retries reached — escalate to orchestrator
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
    -d "text=🚨 סוכן ${LABEL} נכשל אחרי ${RETRIES} ניסיונות. דורש התערבות ידנית." > /dev/null 2>&1
  
  # Wake orchestrator
  curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
    -H "Authorization: Bearer ${HOOK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"task\": \"ESCALATION: Agent ${LABEL} failed after ${RETRIES} retries in topic ${TOPIC}. Investigate the issue. Check logs, test output, and determine if this needs manual intervention. Report to Yossi in Hebrew via message tool: action=send, channel=telegram, target=${CHAT_ID}, threadId=${TOPIC}.\",
      \"sessionKey\": \"hook:escalate:${LABEL}\"
    }" > /dev/null 2>&1
  
  rm -f "$RETRY_FILE"
  exit 1
fi

# Increment retry count
echo $((RETRIES + 1)) > "$RETRY_FILE"
echo "$(date -Iseconds) Retry ${RETRIES} for ${LABEL}" >> /tmp/spawn-task.log
exit 0
