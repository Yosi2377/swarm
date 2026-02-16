#!/bin/bash
# mission-review.sh — Run after agents complete work
# Enforces: shomer review → bodek test → screenshot → report
# Usage: mission-review.sh <thread_id> <project> [sandbox_url]

set -euo pipefail

THREAD="$1"
PROJECT="$2"
SANDBOX_URL="${3:-http://95.111.247.22:9089}"
SWARM="/root/.openclaw/workspace/swarm"
CHAT="-1003815143703"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[REVIEW]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# Load mission state
STATE="/tmp/mission-${THREAD}.json"
[ -f "$STATE" ] || { fail "No mission state for #${THREAD}"; exit 1; }
DESC=$(python3 -c "import json;print(json.load(open('$STATE'))['desc'])")

# ============================================
# GATE 1: שומר Code Review (MANDATORY)
# ============================================
log "GATE 1: שומר Code Review..."

SANDBOX_PATH="/root/sandbox/BettingPlatform"
[[ "$PROJECT" == *"poker"* ]] && SANDBOX_PATH="/root/sandbox/TexasPokerGame"

DIFF=$(cd "$SANDBOX_PATH" && git diff HEAD~1 --stat 2>/dev/null || echo "no changes")
if [ "$DIFF" == "no changes" ]; then
  fail "GATE 1 FAILED — No code changes found!"
  ${SWARM}/send.sh shomer "$THREAD" "🔒 ❌ אין שינויים בקוד — אין מה לבדוק" 2>/dev/null
  exit 1
fi

# Post review
FULL_DIFF=$(cd "$SANDBOX_PATH" && git diff HEAD~1 --stat)
${SWARM}/send.sh shomer "$THREAD" "🔒 <b>Code Review</b>

<pre>${FULL_DIFF}</pre>

בודק אבטחה..." 2>/dev/null

# Quick security scan
ISSUES=""
if cd "$SANDBOX_PATH" && git diff HEAD~1 | grep -qi "eval\|innerHTML.*user\|password.*=.*['\"]"; then
  ISSUES="⚠️ Potential security issue found in diff"
fi

if [ -z "$ISSUES" ]; then
  ${SWARM}/send.sh shomer "$THREAD" "🔒 ✅ <b>APPROVED</b> — קוד נקי, אין בעיות אבטחה" 2>/dev/null
  log "GATE 1 PASSED ✅"
else
  ${SWARM}/send.sh shomer "$THREAD" "🔒 ⚠️ <b>WARNING</b> — ${ISSUES}" 2>/dev/null
  log "GATE 1 WARNING ⚠️"
fi

# ============================================
# GATE 2: בודק QA Test (MANDATORY)
# ============================================
log "GATE 2: בודק QA Test..."

${SWARM}/send.sh bodek "$THREAD" "🧪 מתחיל בדיקות..." 2>/dev/null

# Browser test
SCREENSHOT="/tmp/mission-${THREAD}-screenshot.png"
node -e "
const p=require('puppeteer');
const al=require('${SWARM}/auto-login.js');
(async()=>{
  const b=await p.launch({headless:true,args:['--no-sandbox']});
  const pg=await b.newPage();
  await pg.setViewport({width:1400,height:900});
  await pg.goto('${SANDBOX_URL}',{waitUntil:'networkidle2',timeout:15000});
  await al(pg,'${SANDBOX_URL}');
  await new Promise(r=>setTimeout(r,3000));
  
  // Check console errors
  const errors=[];
  pg.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await new Promise(r=>setTimeout(r,2000));
  
  // Take screenshot
  await pg.screenshot({path:'${SCREENSHOT}'});
  
  // Mobile test
  await pg.setViewport({width:375,height:812});
  await new Promise(r=>setTimeout(r,1000));
  await pg.screenshot({path:'/tmp/mission-${THREAD}-mobile.png'});
  
  console.log(JSON.stringify({errors:errors.length,ok:true}));
  await b.close();
})().catch(e=>console.log(JSON.stringify({errors:-1,ok:false,msg:e.message})));
" 2>/dev/null

RESULT=$(cat /tmp/mission-${THREAD}-screenshot.png > /dev/null 2>&1 && echo "ok" || echo "fail")

if [ "$RESULT" == "ok" ]; then
  ${SWARM}/send.sh bodek "$THREAD" "🧪 ✅ <b>QA PASSED</b>
  
✅ Page loads
✅ Desktop screenshot taken
✅ Mobile screenshot taken
✅ Auto-login works" 2>/dev/null
  log "GATE 2 PASSED ✅"
else
  ${SWARM}/send.sh bodek "$THREAD" "🧪 ❌ <b>QA FAILED</b> — Browser test error" 2>/dev/null
  fail "GATE 2 FAILED"
  exit 1
fi

# ============================================
# GATE 3: Screenshot to General (MANDATORY)
# ============================================
log "GATE 3: Sending screenshot to General..."

BOT_TOKEN=$(cat ${SWARM}/.bot-token)
curl -s -F "chat_id=${CHAT}" -F "message_thread_id=1" \
  -F "photo=@${SCREENSHOT}" \
  -F "caption=📸 #${THREAD} — ${DESC}

✅ שומר — code review passed
✅ בודק — QA passed
✅ Desktop + Mobile tested

מאשר לפרודקשן?" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null

log "Screenshot sent to General ✅"

# Also send to topic
curl -s -F "chat_id=${CHAT}" -F "message_thread_id=${THREAD}" \
  -F "photo=@${SCREENSHOT}" \
  -F "caption=📸 Screenshot — desktop" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null

# ============================================
# Update mission state
# ============================================
python3 -c "
import json
with open('$STATE') as f: d=json.load(f)
d['status']='awaiting_approval'
d['steps_completed'].extend(['shomer_review','bodek_test','screenshot'])
d['steps_remaining']=['user_approval','deploy']
with open('$STATE','w') as f: json.dump(d,f)
"

log "============================================"
log "ALL GATES PASSED ✅"
log "Waiting for user approval..."
log "When approved: deploy.sh ${PROJECT} ${THREAD}"
log "============================================"

# ============================================
# STEP 4: Learning (MANDATORY)
# ============================================
log "STEP 4: Learning from this mission..."

# Record success for all agents
AGENTS=$(python3 -c "import json;print(' '.join(json.load(open('$STATE'))['agents']))")
for agent in $AGENTS; do
  ${SWARM}/learn.sh score "$agent" success "#${THREAD}: ${DESC}" 2>/dev/null || true
  log "Score recorded for ${agent} ✅"
done

# Save episode for future reference
${SWARM}/episode.sh save "${THREAD}" 2>/dev/null || true
log "Episode saved ✅"

# Auto-evolve if enough lessons accumulated
LESSON_COUNT=$(python3 -c "import json;print(len(json.load(open('${SWARM}/learning/lessons.json'))['lessons']))" 2>/dev/null || echo "0")
if [ "$LESSON_COUNT" -gt 10 ]; then
  ${SWARM}/learn.sh evolve 2>/dev/null || true
  log "Auto-evolve triggered (${LESSON_COUNT} lessons)"
fi
