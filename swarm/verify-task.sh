#!/bin/bash
# verify-task.sh — Independent verification after agent reports done (v2)
# Usage: verify-task.sh <agent_id> <thread_id>
# Or:    verify-task.sh <agent_id> <thread_id> <test_command> <project_dir>
#
# If test_command/project_dir not given, reads from /tmp/agent-tasks metadata
# Returns: exit 0 = PASS, exit 1 = FAIL

AGENT_ID="${1:?Usage: verify-task.sh <agent_id> <thread_id> [test_cmd] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TEST_CMD="${3:-}"
PROJECT_DIR="${4:-}"

META_FILE="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"

# Load from metadata if not provided
if [ -z "$TEST_CMD" ] && [ -f "$META_FILE" ]; then
    TEST_CMD=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('test_cmd',''))" < "$META_FILE" 2>/dev/null)
    PROJECT_DIR=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('project_dir',''))" < "$META_FILE" 2>/dev/null)
fi

echo "🔍 INDEPENDENT VERIFICATION: ${AGENT_ID} task ${THREAD_ID}"
echo "📁 Project: ${PROJECT_DIR:-none}"
echo "🧪 Test: ${TEST_CMD:-none}"
echo "========================================="

ISSUES=0
PASS_COUNT=0
FAIL_COUNT=0

# 1. Run test command
if [ -n "$TEST_CMD" ] && [ -n "$PROJECT_DIR" ]; then
    # Kill any process on common ports that might conflict
    for port in 3000 4000 4444 5000 8000; do
        fuser -k ${port}/tcp 2>/dev/null
    done
    sleep 1
    
    cd "$PROJECT_DIR" || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }
    
    OUTPUT=$(eval "$TEST_CMD" 2>&1)
    EXIT_CODE=$?
    
    PASS_COUNT=$(echo "$OUTPUT" | grep -c "✅")
    FAIL_COUNT=$(echo "$OUTPUT" | grep -c "❌")
    
    # Show all failures
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "FAILURES:"
        echo "$OUTPUT" | grep "❌"
        echo ""
    fi
    
    # Show summary
    echo "$OUTPUT" | grep -E "^(Passed|Failed|Total):" 2>/dev/null || true
    
    if [ "$EXIT_CODE" -ne 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
        echo "❌ TESTS FAILED: exit=$EXIT_CODE, ✅=$PASS_COUNT, ❌=$FAIL_COUNT"
        ISSUES=$((ISSUES+1))
    else
        echo "✅ TESTS PASSED: ✅=$PASS_COUNT, ❌=0"
    fi
else
    echo "⚠️ No test command configured — cannot verify automatically"
fi

# 2. Check agent's own completion report
DONE_FILE="/tmp/agent-done/${AGENT_ID}-${THREAD_ID}.json"
if [ -f "$DONE_FILE" ]; then
    AGENT_STATUS=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" < "$DONE_FILE" 2>/dev/null)
    AGENT_TESTS_PASSED=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tests_passed','unknown'))" < "$DONE_FILE" 2>/dev/null)
    echo ""
    echo "Agent self-report: status=${AGENT_STATUS}, tests_passed=${AGENT_TESTS_PASSED}"
    
    # Cross-check: if agent says pass but our tests fail = LIAR
    if [ "$AGENT_TESTS_PASSED" = "True" ] && [ "$FAIL_COUNT" -gt 0 ]; then
        echo "🚨 AGENT LIED: Claimed tests passed but $FAIL_COUNT failures found!"
        ISSUES=$((ISSUES+1))
    fi
else
    echo "⚠️ No structured completion report from agent"
fi

# 3. Check uncommitted changes
if [ -n "$PROJECT_DIR" ] && [ -d "${PROJECT_DIR}/.git" ]; then
    cd "$PROJECT_DIR"
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$DIRTY" -gt 0 ]; then
        echo "⚠️ ${DIRTY} uncommitted changes"
    fi
fi

# 4. Update metadata
if [ -f "$META_FILE" ]; then
    python3 -c "
import json,sys
with open('$META_FILE') as f: d=json.load(f)
d['status']='verified_pass' if $ISSUES==0 else 'verified_fail'
d['verified_at']='$(date -Iseconds)'
d['verify_passed']=$PASS_COUNT
d['verify_failed']=$FAIL_COUNT
d['issues']=$ISSUES
with open('$META_FILE','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
fi

echo ""
echo "========================================="
if [ "$ISSUES" -eq 0 ]; then
    echo "✅ VERIFICATION: PASS"
    exit 0
else
    echo "❌ VERIFICATION: FAIL ($ISSUES issues)"
    exit 1
fi
