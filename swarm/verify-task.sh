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
    # Find the actual screenshot file
    SCREENSHOT_FILE=""
    if [ -n "$PROOF" ] && [ -f "$PROOF" ]; then
        SCREENSHOT_FILE="$PROOF"
    else
        SCREENSHOT_FILE=$(ls /tmp/screenshots/${AGENT_ID}-${THREAD_ID}*.png /tmp/proof-${THREAD_ID}*.png /tmp/report-${THREAD_ID}*.png 2>/dev/null | head -1)
    fi
    
    # Get task description for context
    TASK_DESC=""
    if [ -f "$META_FILE" ]; then
        TASK_DESC=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('task_desc',''))" < "$META_FILE" 2>/dev/null)
    fi
    
    # Analyze screenshot content using pixel analysis + puppeteer page check
    if [ -n "$SCREENSHOT_FILE" ] && [ -n "$TASK_DESC" ]; then
        echo "🔍 Analyzing screenshot content..."
        
        SCREENSHOT_VALID=1
        
        # Check 1: File size — blank/empty screenshots are tiny (<5KB)
        FILE_SIZE=$(stat -c%s "$SCREENSHOT_FILE" 2>/dev/null || echo 0)
        if [ "$FILE_SIZE" -lt 5000 ]; then
            echo "   ⚠️ Screenshot is suspiciously small (${FILE_SIZE} bytes) — likely blank"
            SCREENSHOT_VALID=0
        fi
        
        # Check 2: Use puppeteer to check the actual page for common failure patterns
        # Get URL from report or meta
        CHECK_URL=""
        if [ -f "$DONE_FILE" ]; then
            CHECK_URL=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('url', d.get('proof_url', '')))" < "$DONE_FILE" 2>/dev/null)
        fi
        
        if [ -n "$CHECK_URL" ]; then
            PAGE_CHECK=$(node -e "
const puppeteer = require('puppeteer');
(async () => {
    const browser = await puppeteer.launch({headless: true, args:['--no-sandbox']});
    const page = await browser.newPage();
    try {
        await page.goto('${CHECK_URL}', {waitUntil: 'networkidle2', timeout: 15000});
        const url = page.url();
        const title = await page.title();
        const bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 500) || '');
        
        const issues = [];
        if (url.includes('login') || url.includes('signin')) issues.push('redirected_to_login');
        if (title.toLowerCase().includes('error') || title.includes('404') || title.includes('500')) issues.push('error_page');
        if (bodyText.includes('Cannot GET') || bodyText.includes('Internal Server Error')) issues.push('server_error');
        if (bodyText.length < 50) issues.push('blank_page');
        
        console.log(JSON.stringify({url, title, bodyLength: bodyText.length, issues}));
    } catch(e) {
        console.log(JSON.stringify({error: e.message, issues:['page_load_failed']}));
    }
    await browser.close();
})();
" 2>/dev/null)
            
            PAGE_ISSUES=$(echo "$PAGE_CHECK" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(','.join(d.get('issues',[])))" 2>/dev/null)
            PAGE_TITLE=$(echo "$PAGE_CHECK" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('title',''))" 2>/dev/null)
            
            if [ -n "$PAGE_ISSUES" ]; then
                echo "   ⚠️ Page check found issues: ${PAGE_ISSUES}"
                echo "   Page title: ${PAGE_TITLE}"
                SCREENSHOT_VALID=0
            else
                echo "   Page title: ${PAGE_TITLE}"
                echo "   Page loads correctly ✓"
            fi
        fi
        
        # Check 3: Image color variance — screenshots of error/blank pages have low variance
        COLOR_CHECK=$(python3 -c "
try:
    from PIL import Image
    import statistics
    img = Image.open('${SCREENSHOT_FILE}').convert('L')  # grayscale
    pixels = list(img.getdata())
    variance = statistics.variance(pixels[:10000])
    unique_colors = len(set(pixels[:10000]))
    print(f'{variance:.0f},{unique_colors}')
except: print('0,0')
" 2>/dev/null)
        
        VARIANCE=$(echo "$COLOR_CHECK" | cut -d, -f1)
        UNIQUE=$(echo "$COLOR_CHECK" | cut -d, -f2)
        
        if [ "${VARIANCE:-0}" -lt 100 ] && [ "${UNIQUE:-0}" -lt 20 ]; then
            echo "   ⚠️ Screenshot appears blank/uniform (variance=${VARIANCE}, unique=${UNIQUE})"
            SCREENSHOT_VALID=0
        fi
        
        if [ "$SCREENSHOT_VALID" -eq 1 ]; then
            echo "✅ CHECK 3 PASSED: Screenshot verified — content looks valid"
        else
            echo "❌ CHECK 3 FAILED: Screenshot doesn't show expected result!"
            ISSUES=$((ISSUES+1))
        fi
    else
        echo "✅ CHECK 3 PASSED: Screenshot exists (content check skipped — no context)"
    fi
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
