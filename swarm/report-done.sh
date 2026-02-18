#!/bin/bash
# report-done.sh — Orchestrator uses this EVERY TIME an agent finishes
# Usage: report-done.sh <topic_id> <summary_text> [url_to_screenshot]
#
# This script FORCES the screenshot-first flow:
# 1. Takes screenshot (if URL provided)
# 2. Sends screenshot to General topic
# 3. Sends summary text to General topic
# 4. ONLY THEN the orchestrator can reply to Yossi
#
# If no URL provided, takes screenshot of production site by default

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

if [ ! -f "$SCREENSHOT_PATH" ]; then
  echo "⚠️ Screenshot failed — reporting without image"
  "$SWARM_DIR/send.sh" or 1 "✅ #${TOPIC_ID} הושלם

${SUMMARY}

⚠️ צילום מסך נכשל"
  exit 0
fi

echo "✅ Screenshot taken. Now sending to General..."
echo "SCREENSHOT_PATH=$SCREENSHOT_PATH"
echo "SUMMARY=$SUMMARY"
echo "TOPIC_ID=$TOPIC_ID"
