#!/bin/bash
# verify-task.sh v3 — Independent verification with strict enforcement
# Usage: verify-task.sh <agent_id> <thread_id> [test_cmd] [project_dir]

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
WARNINGS=0
PASS_COUNT=0
FAIL_COUNT=0

# ═══════════════════════════════════════════
# CHECK 1: Run test command
# ═══════════════════════════════════════════
if [ -n "$TEST_CMD" ] && [ -n "$PROJECT_DIR" ]; then
    # Kill conflicting ports
    for port in 3000 4000 4444 5000 8000; do
        fuser -k ${port}/tcp 2>/dev/null
    done
    sleep 1
    
    cd "$PROJECT_DIR" || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }
    
    OUTPUT=$(eval "$TEST_CMD" 2>&1)
    EXIT_CODE=$?
    
    PASS_COUNT=$(echo "$OUTPUT" | grep -c "✅")
    FAIL_COUNT=$(echo "$OUTPUT" | grep -c "❌")
    
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "FAILURES:"
        echo "$OUTPUT" | grep "❌"
        echo ""
    fi
    
    echo "$OUTPUT" | grep -E "^(Passed|Failed|Total):" 2>/dev/null || true
    
    if [ "$EXIT_CODE" -ne 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
        echo "❌ CHECK 1 FAILED: Tests — exit=$EXIT_CODE, ✅=$PASS_COUNT, ❌=$FAIL_COUNT"
        ISSUES=$((ISSUES+1))
    else
        echo "✅ CHECK 1 PASSED: Tests — ✅=$PASS_COUNT, ❌=0"
    fi
else
    echo "⚠️ CHECK 1 SKIPPED: No test command configured"
    WARNINGS=$((WARNINGS+1))
fi

# ═══════════════════════════════════════════
# CHECK 2: Structured completion report
# ═══════════════════════════════════════════
DONE_FILE="/root/.openclaw/workspace/swarm/agent-reports/${AGENT_ID}-${THREAD_ID}.json"
if [ -f "$DONE_FILE" ]; then
    AGENT_STATUS=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" < "$DONE_FILE" 2>/dev/null)
    AGENT_TESTS_PASSED=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tests_passed','unknown'))" < "$DONE_FILE" 2>/dev/null)
    AGENT_SUMMARY=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('summary',''))" < "$DONE_FILE" 2>/dev/null)
    AGENT_PASS=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('test_count',{}).get('passed',0))" < "$DONE_FILE" 2>/dev/null)
    AGENT_FAIL=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('test_count',{}).get('failed',0))" < "$DONE_FILE" 2>/dev/null)
    
    echo ""
    echo "Agent report: status=${AGENT_STATUS}, claimed=${AGENT_PASS}✅/${AGENT_FAIL}❌"
    echo "Agent summary: ${AGENT_SUMMARY}"
    
    # Cross-check: agent claims vs reality
    if [ "$AGENT_TESTS_PASSED" = "True" ] || [ "$AGENT_TESTS_PASSED" = "true" ]; then
        if [ "$FAIL_COUNT" -gt 0 ]; then
            echo "🚨 AGENT LIED: Claimed tests passed but $FAIL_COUNT failures found!"
            ISSUES=$((ISSUES+1))
        fi
    fi
    
    # Cross-check counts
    if [ -n "$AGENT_PASS" ] && [ "$AGENT_PASS" != "0" ] && [ "$PASS_COUNT" -gt 0 ]; then
        if [ "$AGENT_PASS" != "$PASS_COUNT" ]; then
            echo "⚠️ COUNT MISMATCH: Agent claimed ${AGENT_PASS} passed, verify found ${PASS_COUNT}"
            WARNINGS=$((WARNINGS+1))
        fi
    fi
    
    echo "✅ CHECK 2 PASSED: Structured report exists"
else
    echo "❌ CHECK 2 FAILED: No structured report at ${DONE_FILE}"
    ISSUES=$((ISSUES+1))
fi

# ═══════════════════════════════════════════
# CHECK 3: Screenshot proof exists
# ═══════════════════════════════════════════
SCREENSHOT_FOUND=0
# Check in report JSON
if [ -f "$DONE_FILE" ]; then
    PROOF=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('proof_screenshot',''))" < "$DONE_FILE" 2>/dev/null)
    if [ -n "$PROOF" ] && [ -f "$PROOF" ]; then
        SCREENSHOT_FOUND=1
    fi
fi
# Check common screenshot paths
for pattern in "/tmp/screenshots/${AGENT_ID}-${THREAD_ID}"*.png "/tmp/proof-${THREAD_ID}"*.png "/tmp/report-${THREAD_ID}"*.png; do
    ls $pattern 2>/dev/null | head -1 >/dev/null 2>&1 && SCREENSHOT_FOUND=1
done
if [ "$SCREENSHOT_FOUND" -eq 1 ]; then
    echo "✅ CHECK 3 PASSED: Screenshot proof found"
else
    echo "❌ CHECK 3 FAILED: No screenshot proof! Agent must provide visual evidence."
    ISSUES=$((ISSUES+1))
fi

# ═══════════════════════════════════════════
# CHECK 4: Git commits
# ═══════════════════════════════════════════
if [ -n "$PROJECT_DIR" ] && [ -d "${PROJECT_DIR}/.git" ]; then
    cd "$PROJECT_DIR"
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$DIRTY" -gt 0 ]; then
        echo "❌ CHECK 4 FAILED: uncommitted changes"
        git status --porcelain 2>/dev/null | head -5
        ISSUES=$((ISSUES+1))
    else
        echo "✅ CHECK 4 PASSED: All changes committed"
    fi
else
    echo "⚠️ CHECK 4 SKIPPED: No git repo"
    WARNINGS=$((WARNINGS+1))
fi

# ═══════════════════════════════════════════
# UPDATE METADATA
# ═══════════════════════════════════════════
if [ -f "$META_FILE" ]; then
    python3 -c "
import json
with open('$META_FILE') as f: d=json.load(f)
d['status']='verified_pass' if $ISSUES==0 else 'verified_fail'
d['verified_at']='$(date -Iseconds)'
d['verify_passed']=$PASS_COUNT
d['verify_failed']=$FAIL_COUNT
d['verify_issues']=$ISSUES
d['verify_warnings']=$WARNINGS
with open('$META_FILE','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
fi

# ═══════════════════════════════════════════
# VERDICT
# ═══════════════════════════════════════════
echo ""
echo "========================================="
echo "Issues: $ISSUES | Warnings: $WARNINGS"
if [ "$ISSUES" -eq 0 ]; then
    echo "✅ VERIFICATION: PASS"
    exit 0
else
    echo "❌ VERIFICATION: FAIL ($ISSUES issues)"
    exit 1
fi
