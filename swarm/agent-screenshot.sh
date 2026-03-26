#!/bin/bash
# agent-screenshot.sh — Take screenshot and send to topic
# Usage: agent-screenshot.sh <url> <topic_id> <agent_id> <caption>

URL="$1"
TOPIC_ID="$2"
AGENT_ID="$3"
CAPTION="${4:-📸 צילום מסך}"
SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTFILE="/tmp/agent-screenshot-${AGENT_ID}-${TOPIC_ID}-$(date +%s).png"

node -e "
const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({headless: 'new', args: ['--no-sandbox','--disable-dev-shm-usage']});
  const page = await browser.newPage();
  await page.setViewport({width: 1280, height: 800});
  await page.goto('${URL}', {waitUntil: 'networkidle2', timeout: 20000});
  await new Promise(r => setTimeout(r, 2000));
  await page.screenshot({path: '${OUTFILE}', fullPage: false});
  await browser.close();
  console.log('OK');
})();
" 2>/dev/null

if [ -f "$OUTFILE" ]; then
  bash "$SWARM_DIR/send.sh" "$AGENT_ID" "$TOPIC_ID" "$CAPTION" --photo "$OUTFILE"
  echo "$OUTFILE"
else
  echo "SCREENSHOT_FAILED" >&2
  exit 1
fi
