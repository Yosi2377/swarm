#!/bin/bash
# verify-task.sh v4 — INDEPENDENT verification. Trusts NOTHING from agent.
# Usage: verify-task.sh <agent_id> <thread_id> [test_cmd] [project_dir]

AGENT_ID="${1:?Usage: verify-task.sh <agent_id> <thread_id> [test_cmd] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TEST_CMD="${3:-}"
PROJECT_DIR="${4:-}"

META_FILE="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"
REPORT_FILE="/root/.openclaw/workspace/swarm/agent-reports/${AGENT_ID}-${THREAD_ID}.json"

# Load from metadata if not provided
if [ -z "$TEST_CMD" ] && [ -f "$META_FILE" ]; then
    TEST_CMD=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('test_cmd',''))" < "$META_FILE" 2>/dev/null)
    PROJECT_DIR=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('project_dir',''))" < "$META_FILE" 2>/dev/null)
fi

echo "========================================="
echo "🔍 INDEPENDENT VERIFICATION v4"
echo "   Agent: ${AGENT_ID} | Thread: ${THREAD_ID}"
echo "========================================="

ISSUES=0
WARNINGS=0

# ═══════════════════════════════════════════
# CHECK 1: Did the agent actually commit code?
# Not "is working tree clean" but "is there a NEW commit"
# ═══════════════════════════════════════════
if [ -n "$PROJECT_DIR" ] && [ -d "${PROJECT_DIR}/.git" ]; then
    cd "$PROJECT_DIR"
    
    # Check for commits in the last 60 minutes mentioning this thread
    RECENT_COMMITS=$(git log --since="60 minutes ago" --oneline 2>/dev/null)
    THREAD_COMMITS=$(git log --since="60 minutes ago" --oneline --grep="#${THREAD_ID}" 2>/dev/null)
    
    # Also check for uncommitted changes (agent forgot to commit)
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    
    if [ -n "$THREAD_COMMITS" ]; then
        COMMIT_COUNT=$(echo "$THREAD_COMMITS" | wc -l)
        echo "✅ CHECK 1: Found ${COMMIT_COUNT} commit(s) for #${THREAD_ID}:"
        echo "$THREAD_COMMITS" | sed 's/^/   /'
    elif [ -n "$RECENT_COMMITS" ]; then
        echo "⚠️ CHECK 1: Found recent commits but none tagged #${THREAD_ID}:"
        echo "$RECENT_COMMITS" | head -5 | sed 's/^/   /'
        WARNINGS=$((WARNINGS+1))
    else
        if [ "$DIRTY" -gt 0 ]; then
            echo "❌ CHECK 1: No commits AND uncommitted changes found!"
            git status --porcelain 2>/dev/null | head -5 | sed 's/^/   /'
        else
            echo "❌ CHECK 1: No commits at all — agent claims fix but changed NOTHING"
        fi
        ISSUES=$((ISSUES+1))
    fi
    
    # Also flag uncommitted changes
    if [ "$DIRTY" -gt 0 ]; then
        echo "   ⚠️ ${DIRTY} uncommitted file(s) — agent forgot to commit"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "⚠️ CHECK 1 SKIPPED: No git repo at ${PROJECT_DIR:-'(none)'}"
    WARNINGS=$((WARNINGS+1))
fi

# ═══════════════════════════════════════════
# CHECK 2: Run tests independently
# ═══════════════════════════════════════════
PASS_COUNT=0
FAIL_COUNT=0

if [ -n "$TEST_CMD" ] && [ -n "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR" || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }
    
    OUTPUT=$(eval "$TEST_CMD" 2>&1)
    EXIT_CODE=$?
    
    PASS_COUNT=$(echo "$OUTPUT" | grep -c "✅")
    FAIL_COUNT=$(echo "$OUTPUT" | grep -c "❌")
    
    if [ "$EXIT_CODE" -ne 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
        echo "❌ CHECK 2: Tests FAILED (exit=$EXIT_CODE, ✅=$PASS_COUNT, ❌=$FAIL_COUNT)"
        echo "$OUTPUT" | grep "❌" | head -10 | sed 's/^/   /'
        ISSUES=$((ISSUES+1))
    else
        echo "✅ CHECK 2: Tests passed (✅=$PASS_COUNT)"
    fi
    
    # Cross-check: agent claimed different numbers?
    if [ -f "$REPORT_FILE" ]; then
        AGENT_PASS=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('test_count',{}).get('passed',0))" < "$REPORT_FILE" 2>/dev/null)
        AGENT_FAIL=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('test_count',{}).get('failed',0))" < "$REPORT_FILE" 2>/dev/null)
        if [ "$AGENT_PASS" != "$PASS_COUNT" ] || [ "$AGENT_FAIL" != "$FAIL_COUNT" ]; then
            echo "   🚨 MISMATCH: Agent claimed ${AGENT_PASS}✅/${AGENT_FAIL}❌ but actual is ${PASS_COUNT}✅/${FAIL_COUNT}❌"
            WARNINGS=$((WARNINGS+1))
        fi
    fi
else
    echo "⚠️ CHECK 2 SKIPPED: No test command"
    WARNINGS=$((WARNINGS+1))
fi

# ═══════════════════════════════════════════
# CHECK 3: Report file exists
# ═══════════════════════════════════════════
if [ -f "$REPORT_FILE" ]; then
    echo "✅ CHECK 3: Report file exists"
    AGENT_SUMMARY=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('summary','(empty)'))" < "$REPORT_FILE" 2>/dev/null)
    echo "   Summary: ${AGENT_SUMMARY}"
else
    echo "❌ CHECK 3: No report file at ${REPORT_FILE}"
    ISSUES=$((ISSUES+1))
fi

# ═══════════════════════════════════════════
# CHECK 4: Take INDEPENDENT screenshot (don't trust agent's)
# ═══════════════════════════════════════════
VERIFY_URL=""
if [ -f "$REPORT_FILE" ]; then
    VERIFY_URL=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('url', d.get('proof_url', '')))" < "$REPORT_FILE" 2>/dev/null)
fi

if [ -n "$VERIFY_URL" ]; then
    VERIFY_SCREENSHOT="/tmp/verify-${AGENT_ID}-${THREAD_ID}.png"
    echo "📸 Taking INDEPENDENT screenshot of ${VERIFY_URL}..."
    
    PAGE_STATUS=$(node -e "
const puppeteer = require('puppeteer');
(async () => {
    const browser = await puppeteer.launch({headless: true, executablePath: '/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome', args:['--no-sandbox']});
    const page = await browser.newPage();
    await page.setViewport({width: 1400, height: 900});
    try {
        const resp = await page.goto('${VERIFY_URL}', {waitUntil: 'networkidle2', timeout: 15000});
        const status = resp.status();
        const url = page.url();
        const title = await page.title();
        const bodyLen = await page.evaluate(() => document.body?.innerText?.length || 0);
        await new Promise(r => setTimeout(r, 2000));
        await page.screenshot({path: '${VERIFY_SCREENSHOT}', fullPage: false});
        
        const issues = [];
        if (status >= 400) issues.push('http_' + status);
        if (url.includes('login') || url.includes('signin')) issues.push('redirected_to_login');
        if (bodyLen < 50) issues.push('blank_page');
        
        console.log(JSON.stringify({status, url, title, bodyLen, issues, ok: issues.length === 0}));
    } catch(e) {
        console.log(JSON.stringify({error: e.message, issues:['page_load_failed'], ok: false}));
    }
    await browser.close();
})();
" 2>/dev/null)
    
    PAGE_OK=$(echo "$PAGE_STATUS" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('ok', False))" 2>/dev/null)
    PAGE_ISSUES=$(echo "$PAGE_STATUS" | python3 -c "import sys,json; print(','.join(json.loads(sys.stdin.read()).get('issues',[])))" 2>/dev/null)
    HTTP_STATUS=$(echo "$PAGE_STATUS" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('status','?'))" 2>/dev/null)
    
    if [ "$PAGE_OK" = "True" ]; then
        echo "✅ CHECK 4: Independent screenshot OK (HTTP ${HTTP_STATUS})"
        echo "   Screenshot saved: ${VERIFY_SCREENSHOT}"
    else
        echo "❌ CHECK 4: Page has issues: ${PAGE_ISSUES} (HTTP ${HTTP_STATUS})"
        ISSUES=$((ISSUES+1))
    fi
else
    echo "⚠️ CHECK 4 SKIPPED: No URL in report to verify"
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
