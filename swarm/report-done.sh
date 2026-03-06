#!/bin/bash
# report-done.sh — Agent helper: screenshot + summary to topic
# Usage: report-done.sh <topic_id> <summary_text> [url_to_screenshot]
#
# 1. Takes screenshot of the relevant page
# 2. Sends screenshot + summary to the topic
# 3. Also sends to General (topic 1)

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TOPIC_ID="$1"
SUMMARY="$2"
URL="${3:-http://95.111.247.22:9089}"

if [ -z "$TOPIC_ID" ] || [ -z "$SUMMARY" ]; then
  echo "Usage: report-done.sh <topic_id> <summary_text> [url]"
  exit 1
fi

SCREENSHOT_PATH="/tmp/report-${TOPIC_ID}.png"

# Step 1: Take screenshot
echo "📸 Taking screenshot of $URL..."
node -e "
const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: '/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome',
    args: ['--no-sandbox']
  });
  const page = await browser.newPage();
  await page.setViewport({width: 1400, height: 900});
  await page.goto('${URL}', {waitUntil: 'networkidle2', timeout: 15000});
  await new Promise(r => setTimeout(r, 2000));
  // Auto-login for known ports
  const u = await page.\$('#lu'); const p = await page.\$('#lp');
  if (u && p) {
    await u.type('zozo'); await p.type('123456');
    const b = await page.\$('button'); if(b) await b.click();
    await new Promise(r => setTimeout(r, 3000));
  }
  await page.screenshot({path: '${SCREENSHOT_PATH}', fullPage: false});
  await browser.close();
  console.log('Screenshot saved: ${SCREENSHOT_PATH}');
})().catch(e => console.error('Screenshot failed:', e.message));
" 2>&1

# Step 2: Send screenshot to topic
if [ -f "$SCREENSHOT_PATH" ]; then
  echo "✅ Screenshot taken, sending to topic ${TOPIC_ID}..."
  
  # Try each bot token to find the right one
  for AGENT in or koder shomer tzayar worker researcher bodek; do
    TOKEN_FILE="${SWARM_DIR}/.${AGENT}-token"
    if [ -f "$TOKEN_FILE" ]; then
      TOKEN=$(cat "$TOKEN_FILE")
      break
    fi
  done
  
  if [ -n "$TOKEN" ]; then
    # Send to task topic
    curl -sf -F "chat_id=-1003815143703" -F "message_thread_id=${TOPIC_ID}" \
      -F "photo=@${SCREENSHOT_PATH}" -F "caption=📸 ${SUMMARY}" \
      "https://api.telegram.org/bot${TOKEN}/sendPhoto" > /dev/null 2>&1
    
    # Send to General (topic 1)
    curl -sf -F "chat_id=-1003815143703" -F "message_thread_id=1" \
      -F "photo=@${SCREENSHOT_PATH}" -F "caption=✅ #${TOPIC_ID} הושלם: ${SUMMARY}" \
      "https://api.telegram.org/bot${TOKEN}/sendPhoto" > /dev/null 2>&1
    
    echo "✅ Screenshot sent to topic ${TOPIC_ID} and General"
  else
    echo "⚠️ No bot token found, sending text only"
    "$SWARM_DIR/send.sh" or "$TOPIC_ID" "✅ ${SUMMARY} (screenshot at ${SCREENSHOT_PATH})"
  fi
else
  echo "⚠️ Screenshot failed — reporting without image"
  "$SWARM_DIR/send.sh" or "$TOPIC_ID" "✅ ${SUMMARY}
⚠️ צילום מסך נכשל"
fi
