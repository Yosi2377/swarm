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

# Check for screenshot proof
SCREENSHOT_FOUND=0
REPORT_FILE="${SWARM_DIR}/agent-reports/${AGENT_ID}-${THREAD_ID}.json"
LOG_FILE="${SWARM_DIR}/logs/$(date +%Y-%m-%d).jsonl"

# Check in agent report JSON
if [ -f "$REPORT_FILE" ] && grep -qi 'screenshot\|proof.*png\|photo\|📸' "$REPORT_FILE" 2>/dev/null; then
    SCREENSHOT_FOUND=1
fi

# Check in today's log for screenshot mentions from this agent+thread
if [ "$SCREENSHOT_FOUND" -eq 0 ] && [ -f "$LOG_FILE" ]; then
    if grep "\"thread\":.*${THREAD_ID}" "$LOG_FILE" | grep -qi 'screenshot\|proof.*png\|photo\|📸\|sendPhoto'; then
        SCREENSHOT_FOUND=1
    fi
fi

# Check if screenshot file exists
if [ "$SCREENSHOT_FOUND" -eq 0 ] && ls /tmp/proof-${THREAD_ID}*.png /tmp/report-${THREAD_ID}*.png /tmp/screenshot-${THREAD_ID}*.png 2>/dev/null | head -1 >/dev/null 2>&1; then
    SCREENSHOT_FOUND=1
fi

if [ "$SCREENSHOT_FOUND" -eq 0 ]; then
    echo ""
    echo "⚠️ WARNING: No screenshot found for ${AGENT_ID}-${THREAD_ID}"
    echo "חוק ברזל: לפני דיווח done — חובה screenshot!"

    echo "{\"agent\":\"${AGENT_ID}\",\"thread\":${THREAD_ID},\"result\":\"warning_no_screenshot\",\"time\":\"$(date -Iseconds)\"}" \
        >> "${SWARM_DIR}/logs/verifications.jsonl"

    bash "${SWARM_DIR}/send.sh" "${AGENT_ID}" "$THREAD_ID" "⚠️ WARNING: לא נמצא screenshot!
חוק ברזל: לפני דיווח done — חובה screenshot.
השתמש ב: report-done.sh ${THREAD_ID} \"סיכום\" [url]
או: browser action=screenshot
ושלח את התמונה לפני שמדווח done." 2>/dev/null

    echo "RESULT=WARNING_NO_SCREENSHOT"
    # Continue to verification but mark as warning
fi

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
    
    if [ "$SCREENSHOT_FOUND" -eq 0 ]; then
        echo "⚠️ PASS with WARNING — no screenshot provided"
        echo "RESULT=WARNING"
        exit 0
    fi
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
