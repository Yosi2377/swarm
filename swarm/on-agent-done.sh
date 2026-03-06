#!/bin/bash
# on-agent-done.sh v3 — Post-completion verification. Trust NOTHING.
# Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]

AGENT_ID="${1:?Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TEST_CMD="${3:-}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
META_FILE="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"

echo "================================================"
echo "🔍 POST-COMPLETION: ${AGENT_ID} task ${THREAD_ID}"
echo "================================================"

# Get retry count
RETRIES=0
if [ -f "$META_FILE" ]; then
    RETRIES=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('retries',0))" < "$META_FILE" 2>/dev/null || echo 0)
fi

# Run independent verification — this does ALL checks
VERIFY_OUTPUT=$(bash "${SWARM_DIR}/verify-task.sh" "$AGENT_ID" "$THREAD_ID" "$TEST_CMD" "$PROJECT_DIR" 2>&1)
VERIFY_EXIT=$?

echo "$VERIFY_OUTPUT"

if [ "$VERIFY_EXIT" -eq 0 ]; then
    echo ""
    echo "✅ VERIFIED PASS"
    echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"pass\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
        >> "${SWARM_DIR}/logs/verifications.jsonl"
    
    # Send independent screenshot to General as proof
    VERIFY_SCREENSHOT="/tmp/verify-${AGENT_ID}-${THREAD_ID}.png"
    if [ -f "$VERIFY_SCREENSHOT" ]; then
        # Find a bot token
        for AGENT in or koder shomer tzayar worker researcher bodek; do
            TOKEN_FILE="${SWARM_DIR}/.${AGENT}-token"
            if [ -f "$TOKEN_FILE" ]; then
                TOKEN=$(cat "$TOKEN_FILE")
                break
            fi
        done
        if [ -n "$TOKEN" ]; then
            curl -sf -F "chat_id=-1003815143703" -F "message_thread_id=1" \
                -F "photo=@${VERIFY_SCREENSHOT}" \
                -F "caption=✅ #${THREAD_ID} (${AGENT_ID}) — VERIFIED screenshot (taken by verifier)" \
                "https://api.telegram.org/bot${TOKEN}/sendPhoto" > /dev/null 2>&1
        fi
    fi
    
    echo "RESULT=PASS"
    exit 0
else
    RETRIES=$((RETRIES + 1))
    
    # Update retry count
    if [ -f "$META_FILE" ]; then
        python3 -c "
import json
with open('$META_FILE') as f: d=json.load(f)
d['retries']=$RETRIES
d['status']='retry_$RETRIES'
with open('$META_FILE','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
    fi
    
    # Extract specific failures
    FAILURES=$(echo "$VERIFY_OUTPUT" | grep -E "^❌|^   🚨" | head -10)
    
    if [ "$RETRIES" -ge 3 ]; then
        echo ""
        echo "🚨 ESCALATE — failed $RETRIES times"
        echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"escalate\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
            >> "${SWARM_DIR}/logs/verifications.jsonl"
        
        bash "${SWARM_DIR}/send.sh" or 1 "🚨 ${AGENT_ID}-${THREAD_ID} נכשל ${RETRIES} פעמים:
${FAILURES}" 2>/dev/null
        
        echo "RESULT=ESCALATE"
        exit 2
    else
        echo ""
        echo "❌ RETRY ${RETRIES}/3"
        echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"retry\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
            >> "${SWARM_DIR}/logs/verifications.jsonl"
        
        bash "${SWARM_DIR}/send.sh" "${AGENT_ID}" "$THREAD_ID" "❌ VERIFICATION FAILED (retry ${RETRIES}/3):
${FAILURES}

תקן ודווח שוב." 2>/dev/null
        
        echo "RESULT=RETRY"
        exit 1
    fi
fi
