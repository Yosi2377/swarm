#!/bin/bash
# smart-eval.sh — Polls sessions.json until agent finishes, then triggers evaluation
# Usage: nohup bash smart-eval.sh <label> <topic> <eval_instructions> [max_wait_sec] &

LABEL="${1:?Usage: smart-eval.sh <label> <topic> <eval_instructions> [max_wait_sec]}"
TOPIC="${2:-4950}"
EVAL="${3:-Run tests and check the work}"
MAX_WAIT="${4:-300}"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
SESSIONS_FILE="/root/.openclaw/agents/main/sessions/sessions.json"

LOG="/tmp/smart-eval-${LABEL}.log"
echo "$(date -Iseconds) Watching ${LABEL} (max ${MAX_WAIT}s)" > "$LOG"

# Wait 10 seconds for agent to register
sleep 10

# Find the sub-agent session key matching our label
SESSION_KEY=$(python3 -c "
import json
with open('${SESSIONS_FILE}') as f:
    data = json.load(f)
# Find subagent sessions, get the most recent one
candidates = []
for key, val in data.items():
    if 'subagent' in key:
        candidates.append((val.get('updatedAt', 0), key, val.get('sessionId', '')))
candidates.sort(reverse=True)
if candidates:
    print(candidates[0][1])
" 2>/dev/null)

echo "$(date -Iseconds) Tracking session: ${SESSION_KEY}" >> "$LOG"

# Poll until the session stops updating (agent finished)
ELAPSED=10
LAST_UPDATE=0
STABLE_COUNT=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  
  # Read current updatedAt for the session
  CURRENT_UPDATE=$(python3 -c "
import json
with open('${SESSIONS_FILE}') as f:
    data = json.load(f)
for key, val in data.items():
    if 'subagent' in key:
        # Get the most recent subagent update time
        pass
# Check our specific session
session = data.get('${SESSION_KEY}', {})
print(session.get('updatedAt', 0))
" 2>/dev/null)
  
  if [ "$CURRENT_UPDATE" = "$LAST_UPDATE" ] && [ "$LAST_UPDATE" != "0" ]; then
    STABLE_COUNT=$((STABLE_COUNT + 1))
    echo "$(date -Iseconds) No change (stable: ${STABLE_COUNT}) (${ELAPSED}s)" >> "$LOG"
  else
    STABLE_COUNT=0
    LAST_UPDATE="$CURRENT_UPDATE"
    echo "$(date -Iseconds) Session updated (${ELAPSED}s)" >> "$LOG"
  fi
  
  # If no updates for 45 seconds (3 checks), agent is probably done
  if [ $STABLE_COUNT -ge 3 ]; then
    echo "$(date -Iseconds) Agent stable for 45s — treating as done (${ELAPSED}s)" >> "$LOG"
    break
  fi
done

STATUS="done"
if [ $ELAPSED -ge $MAX_WAIT ]; then
  STATUS="timeout"
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
    -d "text=⚠️ סוכן ${LABEL} — timeout (${MAX_WAIT}s). בודק..." > /dev/null 2>&1
else
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
    -d "text=🤖 סוכן ${LABEL} סיים (${ELAPSED}s). מעריך..." > /dev/null 2>&1
fi

# Trigger evaluation
curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
  -H "Authorization: Bearer ${HOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"task\": \"Agent ${LABEL} completed (status: ${STATUS}, time: ${ELAPSED}s). ${EVAL}. RULES: 1) Run the tests/checks specified. 2) If ALL pass → report PASS with details. 3) If ANY fail → report FAIL with exact failures. 4) Send Hebrew report to Telegram: message tool action=send, channel=telegram, target=${CHAT_ID}, threadId=${TOPIC}. Format: ציון PASS/FAIL, סיכום, תוצאות, בעיות.\",
    \"sessionKey\": \"hook:eval:${LABEL}-$(date +%s)\"
  }" >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "$(date -Iseconds) Eval triggered (status: ${STATUS})" >> "$LOG"
