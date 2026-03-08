#!/bin/bash
# auto-verify-and-report.sh — Fully automated post-agent pipeline
# Called by orchestrator after agent done marker detected
# Usage: auto-verify-and-report.sh <agent_id> <thread_id> <url> [summary]
#
# Does EVERYTHING automatically:
# 1. Runs verify-task.sh (contract-based semantic verification)
# 2. Takes its own screenshots (desktop + mobile)
# 3. Sends screenshots to Telegram (topic + General)
# 4. Reports result: PASS → report to Yossi, RETRY → re-queue, ESCALATE → honest report
# 5. Returns JSON with action + details

AGENT_ID="${1:?Usage: auto-verify-and-report.sh <agent_id> <thread_id> <url> [summary]}"
THREAD_ID="${2:?Missing thread_id}"
URL="${3:?Missing URL to verify}"
SUMMARY="${4:-Task completed}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="${AGENT_ID}-${THREAD_ID}"

# Get bot token for Or
OR_TOKEN=$(cat "${SWARM_DIR}/.or-token" 2>/dev/null || cat "${SWARM_DIR}/.bot-token" 2>/dev/null)
if [ -z "$OR_TOKEN" ]; then
  echo '{"action":"error","reason":"No bot token found"}'
  exit 1
fi

CHAT_ID="-1003815143703"

send_photo() {
  local thread="$1" photo="$2" caption="$3"
  curl -sf -F "chat_id=${CHAT_ID}" -F "message_thread_id=${thread}" \
    -F "photo=@${photo}" -F "caption=${caption}" \
    "https://api.telegram.org/bot${OR_TOKEN}/sendPhoto" >/dev/null 2>&1
}

send_msg() {
  local thread="$1" text="$2"
  curl -sf -X POST "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${CHAT_ID}\",\"message_thread_id\":${thread},\"text\":\"${text}\",\"parse_mode\":\"HTML\"}" >/dev/null 2>&1
}

# Step 1: Run semantic verification
VERIFY_RESULT=$(bash "${SWARM_DIR}/verify-task.sh" "$AGENT_ID" "$THREAD_ID" 2>/dev/null)
VERIFY_EXIT=$?

# Step 2: Take screenshots regardless
DESKTOP_SHOT="/tmp/verify-desktop-${THREAD_ID}.png"
MOBILE_SHOT="/tmp/verify-mobile-${THREAD_ID}.png"

# Desktop screenshot (1280px)
node -e "
const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  await page.goto('${URL}', { waitUntil: 'networkidle2', timeout: 15000 }).catch(() => {});
  await page.screenshot({ path: '${DESKTOP_SHOT}', fullPage: false });
  await page.setViewport({ width: 375, height: 812 });
  await page.goto('${URL}', { waitUntil: 'networkidle2', timeout: 15000 }).catch(() => {});
  await page.screenshot({ path: '${MOBILE_SHOT}', fullPage: false });
  await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
" 2>/dev/null

SCREENSHOTS_OK=false
[ -f "$DESKTOP_SHOT" ] && [ -s "$DESKTOP_SHOT" ] && SCREENSHOTS_OK=true

# Step 3: Send screenshots + report based on verify result
case $VERIFY_EXIT in
  0)
    # PASS
    if $SCREENSHOTS_OK; then
      send_photo "$THREAD_ID" "$DESKTOP_SHOT" "📸 Desktop (1280px) — Verified ✅"
      send_photo "1" "$DESKTOP_SHOT" "📸 ${SUMMARY} — Desktop ✅"
      [ -f "$MOBILE_SHOT" ] && send_photo "$THREAD_ID" "$MOBILE_SHOT" "📱 Mobile (375px) — Verified ✅"
    fi
    send_msg "1" "✅ <b>${SUMMARY}</b> הושלם ואומת\n\n🔍 Semantic verification: PASS\n📸 Screenshots attached"
    
    # Update meta
    META="/tmp/agent-tasks/${LABEL}.json"
    [ -f "$META" ] && python3 -c "
import json,sys
d=json.load(open('$META'))
d['status']='verified_pass'
d['verified_at']='$(date -Iseconds)'
json.dump(d,open('$META','w'),indent=2)
" 2>/dev/null
    
    echo "{\"action\":\"pass\",\"summary\":\"${SUMMARY}\",\"screenshots\":${SCREENSHOTS_OK}}"
    ;;
  1)
    # RETRY
    if $SCREENSHOTS_OK; then
      send_photo "$THREAD_ID" "$DESKTOP_SHOT" "📸 Current state — needs fix 🔄"
    fi
    RETRY_PROMPT=$(echo "$VERIFY_RESULT" | grep "RETRY_PROMPT:" | sed 's/RETRY_PROMPT: //')
    send_msg "$THREAD_ID" "🔄 Verification FAILED — retrying with context"
    
    echo "{\"action\":\"retry\",\"prompt\":\"${RETRY_PROMPT}\",\"screenshots\":${SCREENSHOTS_OK}}"
    ;;
  2)
    # ESCALATE
    if $SCREENSHOTS_OK; then
      send_photo "1" "$DESKTOP_SHOT" "🚨 ${SUMMARY} — נכשל אחרי 3 ניסיונות"
    fi
    send_msg "1" "🚨 <b>${SUMMARY}</b> — נכשל\n\nניסינו 3 פעמים. צריך התערבות ידנית.\n\n${VERIFY_RESULT}"
    
    echo "{\"action\":\"escalate\",\"summary\":\"${SUMMARY}\",\"screenshots\":${SCREENSHOTS_OK}}"
    ;;
esac

# Cleanup
rm -f "$DESKTOP_SHOT" "$MOBILE_SHOT" 2>/dev/null
