#!/bin/bash
# smart-eval.sh v3 — Poll → Detect → STRICT Evaluate → Retry/Escalate
# Usage: nohup bash smart-eval.sh <label> <topic> <eval> [max_wait] [original_task] &

LABEL="${1:?Usage: smart-eval.sh <label> <topic> <eval> [max_wait] [original_task]}"
TOPIC="${2:-4950}"
EVAL="${3:-Run tests and check the work}"
MAX_WAIT="${4:-300}"
ORIGINAL_TASK="${5:-}"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
SESSIONS_FILE="/root/.openclaw/agents/main/sessions/sessions.json"
REPORT_DIR="/tmp/agent-reports"
RETRY_FILE="/tmp/retry-${LABEL}.count"
LOG="/tmp/smart-eval-${LABEL}.log"
EVAL_PROMPT=$(cat /root/.openclaw/workspace/swarm/eval-prompt.md 2>/dev/null)

mkdir -p "$REPORT_DIR"
echo "$(date -Iseconds) START: ${LABEL} (max ${MAX_WAIT}s)" > "$LOG"

# ─── PHASE 1: POLL ───
sleep 10
ELAPSED=10
LAST_UPDATE=0
STABLE_COUNT=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  
  CURRENT_UPDATE=$(python3 -c "
import json
with open('${SESSIONS_FILE}') as f:
    data = json.load(f)
best = 0
for key, val in data.items():
    if 'subagent' in key:
        t = val.get('updatedAt', 0)
        if t > best: best = t
print(best)
" 2>/dev/null)
  
  if [ "$CURRENT_UPDATE" = "$LAST_UPDATE" ] && [ "$LAST_UPDATE" != "0" ]; then
    STABLE_COUNT=$((STABLE_COUNT + 1))
  else
    STABLE_COUNT=0
    LAST_UPDATE="$CURRENT_UPDATE"
  fi
  
  if [ $STABLE_COUNT -ge 3 ]; then
    echo "$(date -Iseconds) DONE: stable 45s (${ELAPSED}s)" >> "$LOG"
    break
  fi
done

STATUS="done"
[ $ELAPSED -ge $MAX_WAIT ] && STATUS="timeout"
echo "$(date -Iseconds) STATUS: ${STATUS} (${ELAPSED}s)" >> "$LOG"

# ─── PHASE 2: STRICT EVALUATION ───
curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
  -d "text=🔍 סוכן ${LABEL} ${STATUS} (${ELAPSED}s). בודק בקפדנות..." > /dev/null 2>&1

# Escape the eval prompt for JSON — write to temp file to avoid shell escaping issues
EVAL_TMPFILE="/tmp/eval-payload-${LABEL}.json"
python3 -c "
import json
prompt = open('/root/.openclaw/workspace/swarm/eval-prompt.md').read()
eval_specific = '''${EVAL}'''
payload = {
    'task': f'''STRICT CODE REVIEW for agent ${LABEL} (${STATUS}, ${ELAPSED}s).

{prompt}

SPECIFIC CHECKS:
{eval_specific}

ADDITIONAL MANDATORY CHECKS:
1. Run the tests yourself
2. Read ACTUAL code changes — look for hardcoded/fake data that just passes tests
3. Check: did agent use hardcoded values where real logic is needed?
4. Check: did agent modify test files when told not to?
5. Run: git diff or compare file contents

Write verdict to ${REPORT_DIR}/${LABEL}.json:
{{\"label\":\"${LABEL}\",\"status\":\"pass or fail or suspect\",\"summary\":\"...\",\"tests\":{{\"passed\":N,\"failed\":N,\"total\":N}},\"issues\":[\"...\"],\"verdict_reason\":\"why pass/fail/suspect\"}}

Send Hebrew report to Telegram: message tool action=send, channel=telegram, target=${CHAT_ID}, threadId=${TOPIC}.
Format: PASS ✅ / FAIL ❌ / SUSPECT ⚠️ — details, issues, red flags.''',
    'sessionKey': 'hook:eval:${LABEL}-$(date +%s)'
}
with open('${EVAL_TMPFILE}', 'w') as f:
    json.dump(payload, f, ensure_ascii=False)
" 2>/dev/null

curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
  -H "Authorization: Bearer ${HOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @"${EVAL_TMPFILE}" >> "$LOG" 2>&1

rm -f "${EVAL_TMPFILE}"

echo "" >> "$LOG"
echo "$(date -Iseconds) EVAL sent" >> "$LOG"

# ─── PHASE 3: CHECK RESULT → RETRY/ESCALATE ───
sleep 45

RETRIES=0
[ -f "$RETRY_FILE" ] && RETRIES=$(cat "$RETRY_FILE")

REPORT_STATUS="unknown"
VERDICT_REASON=""
if [ -f "${REPORT_DIR}/${LABEL}.json" ]; then
  REPORT_STATUS=$(python3 -c "
import json
with open('${REPORT_DIR}/${LABEL}.json') as f:
    d = json.load(f)
print(d.get('status', 'unknown'))
" 2>/dev/null)
  VERDICT_REASON=$(python3 -c "
import json
with open('${REPORT_DIR}/${LABEL}.json') as f:
    d = json.load(f)
print(d.get('verdict_reason', '')[:200])
" 2>/dev/null)
fi

echo "$(date -Iseconds) RESULT: ${REPORT_STATUS} reason: ${VERDICT_REASON} (retries: ${RETRIES})" >> "$LOG"

if [ "$REPORT_STATUS" = "fail" ] || [ "$REPORT_STATUS" = "suspect" ]; then
  if [ "$RETRIES" -lt 2 ] && [ -n "$ORIGINAL_TASK" ]; then
    # ─── RETRY ───
    echo $((RETRIES + 1)) > "$RETRY_FILE"
    
    ISSUES=$(python3 -c "
import json
with open('${REPORT_DIR}/${LABEL}.json') as f:
    d = json.load(f)
issues = d.get('issues', [])
print('; '.join(issues)[:200] if issues else 'Unknown')
" 2>/dev/null)
    
    curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
      -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
      -d "text=🔄 ניסיון $((RETRIES + 1))/2 — ${LABEL} נכשל: ${ISSUES}" > /dev/null 2>&1
    
    echo "$(date -Iseconds) RETRY $((RETRIES + 1))" >> "$LOG"
    echo "{\"label\":\"${LABEL}\",\"topic\":\"${TOPIC}\",\"retry\":$((RETRIES + 1)),\"issues\":\"${ISSUES}\"}" > "/tmp/retry-request-${LABEL}.json"
  else
    # ─── ESCALATE ───
    curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
      -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
      -d "text=🚨 ${LABEL} נכשל אחרי ${RETRIES} ניסיונות! בעיות: ${VERDICT_REASON}. דורש התערבות." > /dev/null 2>&1
    
    echo "$(date -Iseconds) ESCALATED" >> "$LOG"
    rm -f "$RETRY_FILE"
  fi
else
  echo "$(date -Iseconds) ✅ DONE" >> "$LOG"
  rm -f "$RETRY_FILE"
fi
