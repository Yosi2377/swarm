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

send_telegram() {
  local target_thread="$1"
  local agent_id="$2"
  local message="$3"
  "$SWARM_DIR/send.sh" "$agent_id" "$target_thread" "$message" > /dev/null 2>&1
}

# ── STEP 1: Notify start ──
log "📋 Starting auto-flow for #$THREAD ($AGENT → $PROJECT)"
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
  log "🔍 Running evaluator (attempt $((RETRY + 1))/$MAX_RETRIES)..."
  
  EVAL_OUTPUT=$("$SWARM_DIR/evaluator.sh" "$THREAD" "$AGENT" 2>&1)
  EVAL_EXIT=$?
  
  echo "$EVAL_OUTPUT"
  
  if [ $EVAL_EXIT -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

while [ $RETRY -lt $MAX_RETRIES ]; do
  if evaluate; then
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
    
    # Send to General with screenshot
    if [ -f "$SCREENSHOT" ]; then
      curl -s -F "chat_id=-1003815143703" -F "message_thread_id=1" \
        -F "photo=@$SCREENSHOT" \
        -F "caption=✅ #$THREAD הושלם — $DESC

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT
🧪 בדיקות: עברו ✅

❓ לדחוף לפרודקשן?" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null 2>&1
    else
      send_telegram 1 "or" "✅ #$THREAD הושלם — $DESC

👤 סוכן: $AGENT
🧪 בדיקות: עברו ✅

❓ לדחוף לפרודקשן?"
    fi
    
    log "📢 Sent results to General"
    exit 0
  else
    RETRY=$((RETRY + 1))
    log "❌ EVALUATION FAILED (attempt $RETRY/$MAX_RETRIES)"
    
    if [ $RETRY -lt $MAX_RETRIES ]; then
      # Send feedback to agent topic
      FEEDBACK=$(cat /tmp/eval-feedback-${THREAD}.txt 2>/dev/null || echo "Tests failed. Check and fix.")
      send_telegram "$THREAD" "$AGENT" "❌ הבדיקות נכשלו (ניסיון $RETRY/$MAX_RETRIES):

$FEEDBACK

תקן ודווח שוב!"
      
      log "📨 Sent feedback to agent, waiting 120s for fix..."
      sleep 120
    fi
  fi
done

# Max retries exhausted
send_telegram 1 "or" "🚨 #$THREAD — נכשל אחרי $MAX_RETRIES ניסיונות!

👤 סוכן: $AGENT
📂 פרויקט: $PROJECT

@יוסי — צריך עזרה ידנית"

log "🚨 Max retries exhausted — escalated to user"
exit 1
