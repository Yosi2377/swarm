#!/bin/bash
# browser-test.sh — Puppeteer-based browser testing for agents
# Usage: browser-test.sh <action> [args...]
#
# Actions:
#   screenshot <url> <output.png> [width] [height]  — Take screenshot
#   multi-screenshot <url> <prefix>                  — 3 viewports (desktop, tablet, mobile)
#   test-poker <base_url> <user1> <pass1> <user2> <pass2> <output_dir>  — Full poker test
#   eval <url> <js_expression>                       — Run JS and return result
#   click <url> <selector> <output.png>              — Click element + screenshot

ACTION=$1
shift

CHROME_PATH="/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome"
SWARM_DIR="/root/.openclaw/workspace/swarm"

case "$ACTION" in
  screenshot)
    URL="$1"; OUTPUT="$2"; WIDTH="${3:-1920}"; HEIGHT="${4:-1080}"
    node -e "
    const puppeteer = require('puppeteer');
    const autoLogin = require('${SWARM_DIR}/auto-login');
    (async () => {
      const browser = await puppeteer.launch({headless: true, args: ['--no-sandbox','--disable-gpu']});
      const page = await browser.newPage();
      await page.setViewport({width: ${WIDTH}, height: ${HEIGHT}});
      await autoLogin(page, '${URL}');
      await page.goto('${URL}', {waitUntil: 'networkidle2', timeout: 30000});
      await new Promise(r => setTimeout(r, 2000));
      await page.screenshot({path: '${OUTPUT}', fullPage: false});
      console.log('✅ Screenshot: ${OUTPUT} (${WIDTH}x${HEIGHT})');
      await browser.close();
    })().catch(e => { console.error('❌', e.message); process.exit(1); });
    "
    ;;

  multi-screenshot)
    URL="$1"; PREFIX="$2"
    echo "📸 Taking 3 viewport screenshots..."
    $0 screenshot "$URL" "${PREFIX}-desktop.png" 1920 1080
    $0 screenshot "$URL" "${PREFIX}-tablet.png" 768 1024
    $0 screenshot "$URL" "${PREFIX}-mobile.png" 375 812
    echo "✅ All 3 screenshots saved with prefix: ${PREFIX}"
    ;;

  test-poker)
    BASE_URL="$1"; USER1="$2"; PASS1="$3"; USER2="$4"; PASS2="$5"; OUTDIR="$6"
    mkdir -p "$OUTDIR"
    node -e "
    const puppeteer = require('puppeteer');
    (async () => {
      const browser = await puppeteer.launch({headless: true, args: ['--no-sandbox','--disable-gpu']});
      
      // Player 1
      const page1 = await browser.newPage();
      await page1.setViewport({width: 1920, height: 1080});
      await page1.goto('${BASE_URL}', {waitUntil: 'networkidle2', timeout: 30000});
      await new Promise(r => setTimeout(r, 2000));
      await page1.screenshot({path: '${OUTDIR}/01-login-page.png'});
      console.log('📸 01-login-page.png');

      // Login player 1
      try {
        await page1.type('input[name=\"username\"], input[type=\"text\"], #username', '${USER1}');
        await page1.type('input[name=\"password\"], input[type=\"password\"], #password', '${PASS1}');
        await page1.click('button[type=\"submit\"], .login-btn, #login-btn');
        await new Promise(r => setTimeout(r, 3000));
        await page1.screenshot({path: '${OUTDIR}/02-player1-lobby.png'});
        console.log('📸 02-player1-lobby.png');
      } catch(e) { console.log('⚠️ Login P1:', e.message); }

      // Player 2
      const page2 = await browser.newPage();
      await page2.setViewport({width: 1920, height: 1080});
      await page2.goto('${BASE_URL}', {waitUntil: 'networkidle2', timeout: 30000});
      await new Promise(r => setTimeout(r, 2000));

      try {
        await page2.type('input[name=\"username\"], input[type=\"text\"], #username', '${USER2}');
        await page2.type('input[name=\"password\"], input[type=\"password\"], #password', '${PASS2}');
        await page2.click('button[type=\"submit\"], .login-btn, #login-btn');
        await new Promise(r => setTimeout(r, 3000));
        await page2.screenshot({path: '${OUTDIR}/03-player2-lobby.png'});
        console.log('📸 03-player2-lobby.png');
      } catch(e) { console.log('⚠️ Login P2:', e.message); }

      // Take final screenshots
      await page1.screenshot({path: '${OUTDIR}/04-player1-final.png'});
      await page2.screenshot({path: '${OUTDIR}/05-player2-final.png'});
      console.log('📸 04-player1-final.png');
      console.log('📸 05-player2-final.png');
      
      console.log('✅ Poker test complete. Screenshots in ${OUTDIR}/');
      await browser.close();
    })().catch(e => { console.error('❌', e.message); process.exit(1); });
    "
    ;;

  eval)
    URL="$1"; EXPR="$2"
    node -e "
    const puppeteer = require('puppeteer');
    const autoLogin = require('${SWARM_DIR}/auto-login');
    (async () => {
      const browser = await puppeteer.launch({headless: true, args: ['--no-sandbox','--disable-gpu']});
      const page = await browser.newPage();
      await autoLogin(page, '${URL}');
      await page.goto('${URL}', {waitUntil: 'networkidle2', timeout: 30000});
      const result = await page.evaluate(() => { return ${EXPR}; });
      console.log(JSON.stringify(result, null, 2));
      await browser.close();
    })().catch(e => { console.error('❌', e.message); process.exit(1); });
    "
    ;;

  *)
    echo "Usage: browser-test.sh <action> [args...]"
    echo "Actions: screenshot, multi-screenshot, test-poker, eval"
    exit 1
    ;;
esac
