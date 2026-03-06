#!/bin/bash
# on-agent-done.sh — Called when a sub-agent reports completion
# Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]
#
# This script:
# 1. Runs independent verification (verify-task.sh)
# 2. If PASS → sends success message to General (thread 1) 
# 3. If FAIL → sends failure details to agent's topic for retry
# 4. Outputs structured result for orchestrator

AGENT_ID="${1:?Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TEST_CMD="${3:-}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "================================================"
echo "🔍 POST-COMPLETION: ${AGENT_ID} task ${THREAD_ID}"
echo "================================================"

# Step 1: Run independent verification
VERIFY_OUTPUT=$(bash "${SWARM_DIR}/verify-task.sh" "$AGENT_ID" "$THREAD_ID" "$TEST_CMD" "$PROJECT_DIR" 2>&1)
VERIFY_EXIT=$?

echo "$VERIFY_OUTPUT"

# Step 2: Check agent's structured report
REPORT_FILE="/tmp/agent-done/${AGENT_ID}-${THREAD_ID}.json"
REPORT_EXISTS="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    AGENT_STATUS=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" < "$REPORT_FILE" 2>/dev/null)
    AGENT_SUMMARY=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('summary','no summary'))" < "$REPORT_FILE" 2>/dev/null)
fi

# Step 3: Act on result
if [ "$VERIFY_EXIT" -eq 0 ]; then
    echo ""
    echo "✅ VERIFIED PASS — reporting to General"
    
    # Log success
    echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"pass\",\"time\":\"$(date -Iseconds)\"}" \
        >> "${SWARM_DIR}/logs/verifications.jsonl"
    
    echo "RESULT=PASS"
else
    # Get retry count
    META_FILE="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"
    RETRIES=0
    if [ -f "$META_FILE" ]; then
        RETRIES=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('retries',0))" < "$META_FILE" 2>/dev/null || echo 0)
        # Increment retry count
        python3 -c "
import json
with open('$META_FILE') as f: d=json.load(f)
d['retries']=int(d.get('retries',0))+1
with open('$META_FILE','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
    fi
    
    RETRIES=$((RETRIES + 1))
    
    echo ""
    if [ "$RETRIES" -ge 3 ]; then
        echo "❌ VERIFIED FAIL — max retries ($RETRIES) reached. ESCALATING."
        
        # Log failure
        echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"fail_escalate\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
            >> "${SWARM_DIR}/logs/verifications.jsonl"
        
        echo "RESULT=ESCALATE"
    else
        echo "❌ VERIFIED FAIL — retry ${RETRIES}/3. Sending back to agent."
        
        # Send failure details to agent's topic
        FAILURES=$(echo "$VERIFY_OUTPUT" | grep "❌" | head -5)
        bash "${SWARM_DIR}/send.sh" or "$THREAD_ID" "❌ VERIFICATION FAILED (retry ${RETRIES}/3):
${FAILURES}

תקן ודווח שוב." 2>/dev/null
        
        # Log retry
        echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"fail_retry\",\"retries\":${RETRIES},\"time\":\"$(date -Iseconds)\"}" \
            >> "${SWARM_DIR}/logs/verifications.jsonl"
        
        echo "RESULT=RETRY"
    fi
fi
