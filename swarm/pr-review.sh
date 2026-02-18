#!/bin/bash
# PR Review + Merge workflow
# Usage: pr-review.sh TASK_ID BRANCH_NAME SUMMARY

TASK_ID="$1"
BRANCH_NAME="$2"
SUMMARY="$3"

if [ -z "$TASK_ID" ] || [ -z "$BRANCH_NAME" ] || [ -z "$SUMMARY" ]; then
  echo "Usage: pr-review.sh TASK_ID BRANCH_NAME SUMMARY"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"

# 1. Get diff stats
cd "$WORKSPACE" || exit 1
DIFF=$(git diff master.."$BRANCH_NAME" --stat 2>/dev/null || echo "no diff")

# 2. Screenshot
echo "📸 Taking screenshot..."
node -e "const p=require('puppeteer');(async()=>{const b=await p.launch({headless:true,executablePath:'/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome',args:['--no-sandbox']});const pg=await b.newPage();await pg.setViewport({width:1400,height:900});await pg.goto('http://95.111.247.22:9089',{waitUntil:'networkidle2',timeout:15000});await new Promise(r=>setTimeout(r,3000));await pg.screenshot({path:'/tmp/pr-${TASK_ID}.png'});await b.close()})()" 2>/dev/null
SCREENSHOT_OK=$?

# 3. Send to General
MSG="📋 PR #${TASK_ID} — ${SUMMARY}
📊 ${DIFF}

✅ /approve — merge+deploy
❌ /reject — לתקן"

"$SCRIPT_DIR/send.sh" or 1 "$MSG"

# Send screenshot if taken successfully
if [ $SCREENSHOT_OK -eq 0 ] && [ -f "/tmp/pr-${TASK_ID}.png" ]; then
  TOKEN=$(cat "$SCRIPT_DIR/.or-token" 2>/dev/null)
  if [ -n "$TOKEN" ]; then
    curl -sf -F "chat_id=-1003815143703" -F "message_thread_id=1" \
      -F "photo=@/tmp/pr-${TASK_ID}.png" -F "caption=📸 PR #${TASK_ID} — ${SUMMARY}" \
      "https://api.telegram.org/bot${TOKEN}/sendPhoto" >/dev/null 2>&1
  fi
fi

echo "✅ PR #${TASK_ID} sent to General"
