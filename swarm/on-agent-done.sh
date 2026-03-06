#!/bin/bash
# on-agent-done.sh v2 — Post-completion pipeline with strict verification
# Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]

AGENT_ID="${1:?Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TEST_CMD="${3:-}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${SWARM_DIR}/logs"

echo "================================================"
echo "🔍 POST-COMPLETION: ${AGENT_ID} task ${THREAD_ID}"
echo "================================================"

# Run independent verification
VERIFY_OUTPUT=$(bash "${SWARM_DIR}/verify-task.sh" "$AGENT_ID" "$THREAD_ID" "$TEST_CMD" "$PROJECT_DIR" 2>&1)
VERIFY_EXIT=$?

echo "$VERIFY_OUTPUT"

# Get retry count from metadata
META_FILE="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"
RETRIES=0
if [ -f "$META_FILE" ]; then
    RETRIES=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('retries',0))" < "$META_FILE" 2>/dev/null || echo 0)
fi

if [ "$VERIFY_EXIT" -eq 0 ]; then
    echo ""
    echo "✅ VERIFIED PASS"
    
    # Log
    echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"pass\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
        >> "${SWARM_DIR}/logs/verifications.jsonl"
    
    echo "RESULT=PASS"
    exit 0
else
    # Increment retry count
    RETRIES=$((RETRIES + 1))
    if [ -f "$META_FILE" ]; then
        python3 -c "
import json
with open('$META_FILE') as f: d=json.load(f)
d['retries']=$RETRIES
d['status']='retry_$RETRIES'
with open('$META_FILE','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
    fi
    
    # Extract specific failures for retry message
    FAILURES=$(echo "$VERIFY_OUTPUT" | grep -E "^❌" | head -10)
    
    if [ "$RETRIES" -ge 3 ]; then
        echo ""
        echo "🚨 ESCALATE — max retries ($RETRIES) reached"
        
        echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"escalate\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
            >> "${SWARM_DIR}/logs/verifications.jsonl"
        
        # Notify orchestrator in General
        bash "${SWARM_DIR}/send.sh" or 1 "🚨 ${AGENT_ID}-${THREAD_ID} נכשל 3 פעמים. דורש התערבות:
${FAILURES}" 2>/dev/null
        
        echo "RESULT=ESCALATE"
        exit 2
    else
        echo ""
        echo "❌ RETRY ${RETRIES}/3"
        
        echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"retry\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
            >> "${SWARM_DIR}/logs/verifications.jsonl"
        
        # Send detailed failure to agent's topic
        bash "${SWARM_DIR}/send.sh" "${AGENT_ID}" "$THREAD_ID" "❌ VERIFICATION FAILED (retry ${RETRIES}/3):
${FAILURES}

תקן את הבעיות ודווח שוב. זכור:
1. git add -A && git commit
2. כתוב /root/.openclaw/workspace/swarm/agent-reports/${AGENT_ID}-${THREAD_ID}.json
3. כל הטסטים חייבים לעבור" 2>/dev/null
        
        echo "RESULT=RETRY"
        exit 1
    fi
fi
