#!/bin/bash
# auto-flow.sh — Full automated task flow
# Usage: auto-flow.sh <agent_id> <thread_id> <project> <task_description>
#
# Flow:
# 1. Send task to agent topic
# 2. Wait for agent to finish (monitor session)
# 3. Run evaluator.sh automatically
# 4. If FAIL → send feedback, retry (up to 3)
# 5. If PASS → screenshot + post to General
# 6. Ask user for approval

set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="${1:?Usage: auto-flow.sh <agent_id> <thread_id> <project> <description>}"
THREAD="${2:?}"
PROJECT="${3:?}"
DESC="${4:-Task $THREAD}"
MAX_RETRIES=3
RETRY=0
BOT_TOKEN=$(cat "$SWARM_DIR/.bot-token" 2>/dev/null)

log() { echo "[$(date '+%H:%M:%S')] $1"; }

feed() {
  local step="$1"
  local msg="${2:-}"
  "$SWARM_DIR/live-feed.sh" "$AGENT" "$THREAD" "$step" "$msg" 2>/dev/null
}

send_telegram() {
  local target_thread="$1"
  local agent_id="$2"
  local message="$3"
  "$SWARM_DIR/send.sh" "$agent_id" "$target_thread" "$message" > /dev/null 2>&1
}

# ── STEP 0: Inject lessons before agent starts ──
log "🧠 Injecting lessons for $AGENT..."
INJECT_CTX=$("$SWARM_DIR/learn.sh" inject "$AGENT" "$PROJECT" 2>/dev/null || echo "")
QUERY_CTX=$("$SWARM_DIR/learn.sh" query "$DESC" 2>/dev/null || echo "")
LESSON_BLOCK=""
if [ -n "$INJECT_CTX" ] || [ -n "$QUERY_CTX" ]; then
  LESSON_BLOCK="
💡 לקחים מהעבר:
$INJECT_CTX
$QUERY_CTX
⚠️ שים לב לטעויות האלה!"
fi

# ── STEP 1: Notify start ──
log "📋 Starting auto-flow for #$THREAD ($AGENT → $PROJECT)"
feed "start" "$DESC"
send_telegram 1 "or" "🐝 #$THREAD — $DESC
👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
⏳ עובד..."

# ── STEP 2: Monitor agent (check session activity) ──
# We poll the task file for "done" or "completed" status
# Also check if agent session was recently active
WAIT_MAX=600  # 10 minutes max wait
WAIT_INTERVAL=30
WAITED=0

log "⏳ Waiting for agent to finish (max ${WAIT_MAX}s)..."

while [ $WAITED -lt $WAIT_MAX ]; do
  sleep $WAIT_INTERVAL
  WAITED=$((WAITED + WAIT_INTERVAL))
  
  # Check if task file was marked done
  TASK_FILE="$SWARM_DIR/tasks/$THREAD.md"
  if [ -f "$TASK_FILE" ]; then
    if grep -qi "status:.*done\|status:.*completed\|✅.*הושלם\|## Tests" "$TASK_FILE" 2>/dev/null; then
      log "📝 Task file indicates completion"
      break
    fi
  fi
  
  # Check git for recent commits mentioning this thread
  cd "$SWARM_DIR/.." 2>/dev/null
  RECENT_COMMITS=$(git log --since="$((WAITED))seconds ago" --oneline 2>/dev/null | grep -c "$THREAD" || true)
  if [ "$RECENT_COMMITS" -gt 0 ] && [ $WAITED -gt 120 ]; then
    # Had commits but stopped — might be done
    LAST_COMMIT_AGE=$(( $(date +%s) - $(git log -1 --format=%ct 2>/dev/null || echo "0") ))
    if [ "$LAST_COMMIT_AGE" -gt 60 ]; then
      log "📝 No new commits for ${LAST_COMMIT_AGE}s — assuming done"
      break
    fi
  fi
  
  log "⏳ Waiting... (${WAITED}s / ${WAIT_MAX}s)"
done

# ── STEP 3: Run evaluator ──
evaluate() {
  feed "eval" "ניסיון $((RETRY + 1))/$MAX_RETRIES"
  log "🔍 Running evaluator (attempt $((RETRY + 1))/$MAX_RETRIES)..."
  
  EVAL_OUTPUT=$("$SWARM_DIR/evaluator.sh" "$THREAD" "$AGENT" 2>&1)
  EVAL_EXIT=$?
  
  echo "$EVAL_OUTPUT"
  
  if [ $EVAL_EXIT -eq 0 ]; then
    return 0
  else
    # Save errors for Phase 2 history
    echo "$EVAL_OUTPUT" >> "/tmp/eval-errors-${THREAD}.txt"
    return 1
  fi
}

while [ $RETRY -lt $MAX_RETRIES ]; do
  if evaluate; then
    # Learn from success
    "$SWARM_DIR/learn.sh" lesson "$AGENT" "low" "success #$THREAD" "$DESC" 2>/dev/null || true
    "$SWARM_DIR/learn.sh" score "$AGENT" success "$DESC" 2>/dev/null || true
    feed "pass" "כל הבדיקות עברו!"
    log "✅ EVALUATION PASSED!"
    
    # Take screenshot
    SCREENSHOT="/tmp/auto-flow-${THREAD}.png"
    node -e "
    const puppeteer = require('puppeteer');
    (async () => {
      const browser = await puppeteer.launch({headless:true, executablePath:'/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome', args:['--no-sandbox']});
      const page = await browser.newPage();
      await page.setViewport({width:1400, height:900});
      const urls = {
        'betting': 'http://95.111.247.22:8089',
        'poker': 'https://zozopoker.duckdns.org',
        'dashboard': 'http://95.111.247.22:8090'
      };
      await page.goto(urls['$PROJECT'] || 'http://95.111.247.22:8090', {waitUntil:'networkidle2', timeout:10000});
      await new Promise(r=>setTimeout(r,2000));
      await page.screenshot({path:'$SCREENSHOT', fullPage:false});
      await browser.close();
    })();" 2>/dev/null
    
    # Send screenshot to task topic, text summary to General
    if [ -f "$SCREENSHOT" ]; then
      # Screenshot → task topic (General blocks photos)
      curl -s -F "chat_id=-1003815143703" -F "message_thread_id=$THREAD" \
        -F "photo=@$SCREENSHOT" \
        -F "caption=✅ #$THREAD הושלם — $DESC

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
🧪 בדיקות: עברו ✅" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null 2>&1
    fi
    
    # Text summary → General (always works)
    send_telegram 1 "or" "✅ #$THREAD הושלם — $DESC

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
🧪 בדיקות: עברו ✅
📸 ראה screenshots ב-#$THREAD

❓ לדחוף לפרודקשן?"
    
    feed "done" "נשלח ליוסי לאישור"
    log "📢 Sent results to General"
    exit 0
  else
    RETRY=$((RETRY + 1))
    # Learn from failure
    "$SWARM_DIR/learn.sh" lesson "$AGENT" "medium" "eval fail #$THREAD attempt $RETRY" "$EVAL_OUTPUT" 2>/dev/null || true
    "$SWARM_DIR/learn.sh" score "$AGENT" fail "$DESC" 2>/dev/null || true
    feed "fail" "ניסיון $RETRY/$MAX_RETRIES"
    log "❌ EVALUATION FAILED (attempt $RETRY/$MAX_RETRIES)"
    
    if [ $RETRY -lt $MAX_RETRIES ]; then
      # Send feedback to agent topic
      FEEDBACK=$(cat /tmp/eval-feedback-${THREAD}.txt 2>/dev/null || echo "Tests failed. Check and fix.")
      send_telegram "$THREAD" "$AGENT" "❌ הבדיקות נכשלו (ניסיון $RETRY/$MAX_RETRIES):

$FEEDBACK

תקן ודווח שוב!"
      
      feed "feedback" "$(head -3 /tmp/eval-feedback-${THREAD}.txt 2>/dev/null || echo 'fix needed')"
      log "📨 Sent feedback to agent, waiting 120s for fix..."
      sleep 120
    fi
  fi
done

# ── PHASE 2: New approach after Phase 1 fails ──
log "🔄 Phase 1 exhausted ($MAX_RETRIES retries). Starting Phase 2 — new approach..."
feed "phase2" "Phase 1 נכשל — מתחיל גישה חדשה"

ERRORS_HISTORY=$(cat "/tmp/eval-errors-${THREAD}.txt" 2>/dev/null || echo "unknown")

# Log lesson for learning system
"$SWARM_DIR/learn.sh" lesson "$AGENT" "high" "Failed 3 times on #$THREAD" "Errors: $(echo "$ERRORS_HISTORY" | tail -20)" 2>/dev/null || true

# Get past lessons for similar tasks
LESSONS=$("$SWARM_DIR/learn.sh" query "$DESC" 2>/dev/null | head -10 || echo "אין לקחים קודמים")

# Send agent the new approach message
send_telegram "$THREAD" "$AGENT" "❌ Phase 1 נכשל (3 ניסיונות).

📝 מה נכשל:
$(echo "$ERRORS_HISTORY" | tail -30)

💡 לקחים מהעבר:
$LESSONS

🔄 נסה גישה אחרת לגמרי!
- מה שעשית עד עכשיו לא עבד
- חשוב על פתרון שונה
- אם השתמשת בגישה X, נסה Y"

# Notify General
send_telegram 1 "or" "🔄 #$THREAD — Phase 2: גישה חדשה
👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
❌ Phase 1 נכשל אחרי $MAX_RETRIES ניסיונות
🧠 נשלחו לקחים מהעבר לסוכן"

# Wait for agent to work on new approach
log "⏳ Waiting for agent to implement new approach (max ${WAIT_MAX}s)..."
WAITED=0
while [ $WAITED -lt $WAIT_MAX ]; do
  sleep $WAIT_INTERVAL
  WAITED=$((WAITED + WAIT_INTERVAL))
  
  TASK_FILE="$SWARM_DIR/tasks/$THREAD.md"
  if [ -f "$TASK_FILE" ]; then
    if grep -qi "status:.*done\|status:.*completed\|✅.*הושלם" "$TASK_FILE" 2>/dev/null; then
      log "📝 Task file indicates completion (Phase 2)"
      break
    fi
  fi
  
  cd "$SWARM_DIR/.." 2>/dev/null
  if [ $WAITED -gt 120 ]; then
    LAST_COMMIT_AGE=$(( $(date +%s) - $(git log -1 --format=%ct 2>/dev/null || echo "0") ))
    if [ "$LAST_COMMIT_AGE" -gt 60 ]; then
      log "📝 No new commits for ${LAST_COMMIT_AGE}s — assuming done (Phase 2)"
      break
    fi
  fi
  
  log "⏳ Phase 2 waiting... (${WAITED}s / ${WAIT_MAX}s)"
done

# Phase 2 evaluation loop
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
  if evaluate; then
    # Learn from Phase 2 success
    "$SWARM_DIR/learn.sh" lesson "$AGENT" "low" "Phase 2 success #$THREAD" "$DESC" 2>/dev/null || true
    "$SWARM_DIR/learn.sh" score "$AGENT" success "$DESC" 2>/dev/null || true
    feed "pass" "Phase 2 — כל הבדיקות עברו!"
    log "✅ PHASE 2 EVALUATION PASSED!"
    
    # Same success flow as Phase 1
    SCREENSHOT="/tmp/auto-flow-${THREAD}.png"
    node -e "
    const puppeteer = require('puppeteer');
    (async () => {
      const browser = await puppeteer.launch({headless:true, executablePath:'/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome', args:['--no-sandbox']});
      const page = await browser.newPage();
      await page.setViewport({width:1400, height:900});
      const urls = {
        'betting': 'http://95.111.247.22:8089',
        'poker': 'https://zozopoker.duckdns.org',
        'dashboard': 'http://95.111.247.22:8090'
      };
      await page.goto(urls['$PROJECT'] || 'http://95.111.247.22:8090', {waitUntil:'networkidle2', timeout:10000});
      await new Promise(r=>setTimeout(r,2000));
      await page.screenshot({path:'$SCREENSHOT', fullPage:false});
      await browser.close();
    })();" 2>/dev/null
    
    if [ -f "$SCREENSHOT" ]; then
      curl -s -F "chat_id=-1003815143703" -F "message_thread_id=$THREAD" \
        -F "photo=@$SCREENSHOT" \
        -F "caption=✅ #$THREAD הושלם (Phase 2) — $DESC

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
🧪 בדיקות: עברו ✅" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null 2>&1
    fi
    
    send_telegram 1 "or" "✅ #$THREAD הושלם (Phase 2!) — $DESC

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
🧪 בדיקות: עברו ✅ (גישה חדשה עבדה)
📸 ראה screenshots ב-#$THREAD

❓ לדחוף לפרודקשן?"
    
    feed "done" "Phase 2 הצליח! נשלח ליוסי לאישור"
    log "📢 Phase 2 success — sent to General"
    exit 0
  else
    RETRY=$((RETRY + 1))
    # Learn from Phase 2 failure
    "$SWARM_DIR/learn.sh" lesson "$AGENT" "medium" "Phase 2 eval fail #$THREAD attempt $RETRY" "$EVAL_OUTPUT" 2>/dev/null || true
    "$SWARM_DIR/learn.sh" score "$AGENT" fail "$DESC" 2>/dev/null || true
    feed "fail" "Phase 2 ניסיון $RETRY/$MAX_RETRIES"
    log "❌ PHASE 2 EVALUATION FAILED (attempt $RETRY/$MAX_RETRIES)"
    
    if [ $RETRY -lt $MAX_RETRIES ]; then
      FEEDBACK=$(cat /tmp/eval-feedback-${THREAD}.txt 2>/dev/null || echo "Tests failed. Check and fix.")
      send_telegram "$THREAD" "$AGENT" "❌ Phase 2 — הבדיקות נכשלו (ניסיון $RETRY/$MAX_RETRIES):

$FEEDBACK

תקן ודווח שוב! (גישה חדשה)"
      
      feed "feedback" "Phase 2: $(head -3 /tmp/eval-feedback-${THREAD}.txt 2>/dev/null || echo 'fix needed')"
      log "📨 Phase 2 feedback sent, waiting 120s..."
      sleep 120
    fi
  fi
done

# Both phases exhausted — escalate
FULL_ERRORS=$(cat "/tmp/eval-errors-${THREAD}.txt" 2>/dev/null | tail -50 || echo "no error log")
send_telegram 1 "or" "🚨 #$THREAD — נכשל אחרי 2 שלבים (6 ניסיונות)!

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT

📝 שגיאות אחרונות:
$(echo "$FULL_ERRORS" | tail -10)

@יוסי — צריך עזרה ידנית"

"$SWARM_DIR/learn.sh" lesson "$AGENT" "critical" "Failed both phases on #$THREAD ($DESC)" "Total 6 retries exhausted" 2>/dev/null || true

feed "error" "נכשל אחרי 6 ניסיונות (2 שלבים) — צריך עזרה"
log "🚨 Both phases exhausted — escalated to user"
exit 1
