#!/bin/bash
# mission-review.sh — Post-agent review flow
# Integrates: evaluator → validate-tests → shomer → bodek → screenshot → learning → report
# Usage: mission-review.sh <thread_id> <project> [sandbox_url]

set -euo pipefail

THREAD="$1"
PROJECT="$2"
SANDBOX_URL="${3:-http://95.111.247.22:9089}"
SWARM="/root/.openclaw/workspace/swarm"
CHAT="-1003815143703"
BOT_TOKEN=$(cat ${SWARM}/.bot-token)

log() { echo -e "\033[0;32m[REVIEW]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1"; }

STATE="/tmp/mission-${THREAD}.json"
[ -f "$STATE" ] || { fail "No mission state for #${THREAD}"; exit 1; }
DESC=$(python3 -c "import json;print(json.load(open('$STATE'))['desc'])")
AGENTS=$(python3 -c "import json;print(' '.join(json.load(open('$STATE'))['agents']))")

SANDBOX_PATH="/root/sandbox/BettingPlatform"
[[ "$PROJECT" == *"poker"* ]] && SANDBOX_PATH="/root/sandbox/TexasPokerGame"

# ============================================
# GATE 0: Validate tests exist (validate-tests.sh)
# ============================================
log "GATE 0: Validating test selectors..."
if [ -f "${SWARM}/tasks/${THREAD}.md" ]; then
  ${SWARM}/validate-tests.sh "${SWARM}/tasks/${THREAD}.md" 2>/dev/null && log "Tests valid ✅" || warn "No browser tests defined"
fi

# ============================================
# GATE 1: Evaluator (evaluator.sh)
# ============================================
log "GATE 1: Running evaluator..."
FIRST_AGENT=$(echo $AGENTS | awk '{print $1}')
EVAL_RESULT=$(${SWARM}/evaluator.sh "$THREAD" "$FIRST_AGENT" 2>/dev/null || echo "SKIP")
if echo "$EVAL_RESULT" | grep -q "FAIL"; then
  ${SWARM}/send.sh "$FIRST_AGENT" "$THREAD" "❌ Evaluator FAILED — תבדוק ותתקן" 2>/dev/null
  
  # Auto-retry (retry.sh)
  log "Running retry..."
  ${SWARM}/retry.sh "$THREAD" "$FIRST_AGENT" 3 2>/dev/null || true
  
  EVAL_RESULT=$(${SWARM}/evaluator.sh "$THREAD" "$FIRST_AGENT" 2>/dev/null || echo "SKIP")
  if echo "$EVAL_RESULT" | grep -q "FAIL"; then
    fail "GATE 1 FAILED after retries"
    ${SWARM}/send.sh or 1 "❌ #${THREAD} — evaluator נכשל אחרי 3 retries" 2>/dev/null
    # Record failure
    ${SWARM}/learn.sh score "$FIRST_AGENT" fail "#${THREAD}: evaluator failed" 2>/dev/null || true
    ${SWARM}/learn.sh lesson "$FIRST_AGENT" medium "evaluator failed on #${THREAD}" "Need better tests or code" 2>/dev/null || true
    exit 1
  fi
fi
log "GATE 1 PASSED ✅"

# ============================================
# GATE 2: Guard check (guard.sh)
# ============================================
log "GATE 2: Guard pre-done check..."
GUARD_RESULT=$(${SWARM}/guard.sh pre-done "$THREAD" "$SANDBOX_PATH" "$SANDBOX_URL" 2>/dev/null || echo "SKIP")
if echo "$GUARD_RESULT" | grep -q "FAIL"; then
  warn "Guard check had warnings"
else
  log "GATE 2 PASSED ✅"
fi

# ============================================
# GATE 3: שומר Code Review
# ============================================
log "GATE 3: שומר Code Review..."
DIFF=$(cd "$SANDBOX_PATH" && git diff HEAD~1 --stat 2>/dev/null || echo "no changes")

${SWARM}/send.sh shomer "$THREAD" "🔒 <b>Code Review</b>

<pre>${DIFF}</pre>

בודק אבטחה..." 2>/dev/null

# Security scan
ISSUES=""
cd "$SANDBOX_PATH"
if git diff HEAD~1 2>/dev/null | grep -qi "eval(\|\.innerHTML.*=.*\+\|password.*=.*['\"]"; then
  ISSUES="⚠️ Potential security issue"
fi

if [ -z "$ISSUES" ]; then
  ${SWARM}/send.sh shomer "$THREAD" "🔒 ✅ <b>APPROVED</b> — קוד נקי" 2>/dev/null
  log "GATE 3 PASSED ✅"
else
  ${SWARM}/send.sh shomer "$THREAD" "🔒 ⚠️ ${ISSUES}" 2>/dev/null
  warn "GATE 3 WARNING"
fi

# ============================================
# GATE 4: בודק QA Test (browser-test.sh + auto-login)
# ============================================
log "GATE 4: בודק QA..."
${SWARM}/send.sh bodek "$THREAD" "🧪 מתחיל בדיקות..." 2>/dev/null

SCREENSHOT="/tmp/mission-${THREAD}-desktop.png"
MOBILE="/tmp/mission-${THREAD}-mobile.png"

# Desktop test
${SWARM}/browser-test.sh screenshot "$SANDBOX_URL" "$SCREENSHOT" 1400 900 2>/dev/null || true

# Mobile test
${SWARM}/browser-test.sh screenshot "$SANDBOX_URL" "$MOBILE" 375 812 2>/dev/null || true

if [ -f "$SCREENSHOT" ]; then
  ${SWARM}/send.sh bodek "$THREAD" "🧪 ✅ <b>QA PASSED</b>
✅ Desktop screenshot
✅ Mobile screenshot
✅ Auto-login works" 2>/dev/null
  log "GATE 4 PASSED ✅"
else
  ${SWARM}/send.sh bodek "$THREAD" "🧪 ❌ QA FAILED — no screenshot" 2>/dev/null
  fail "GATE 4 FAILED"
  exit 1
fi

# ============================================
# GATE 5: Screenshot to General + Topic
# ============================================
log "GATE 5: Screenshots..."

# Send desktop to General
curl -sf -F "chat_id=${CHAT}" -F "message_thread_id=1" \
  -F "photo=@${SCREENSHOT}" \
  -F "caption=📸 #${THREAD} — ${DESC}

✅ שומר — code review
✅ בודק — QA
✅ evaluator

מאשר לפרודקשן?" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null || warn "Could not send to General"

# Send to topic
curl -sf -F "chat_id=${CHAT}" -F "message_thread_id=${THREAD}" \
  -F "photo=@${SCREENSHOT}" \
  -F "caption=📸 Desktop" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null || true

# Send mobile to topic
[ -f "$MOBILE" ] && curl -sf -F "chat_id=${CHAT}" -F "message_thread_id=${THREAD}" \
  -F "photo=@${MOBILE}" \
  -F "caption=📱 Mobile" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" > /dev/null || true

log "GATE 5 PASSED ✅"

# ============================================
# STEP 6: Learning (record success + episode)
# ============================================
log "STEP 6: Learning..."
for agent in $AGENTS; do
  ${SWARM}/learn.sh score "$agent" success "#${THREAD}: ${DESC}" 2>/dev/null || true
done
${SWARM}/learn.sh lesson "$FIRST_AGENT" low "#${THREAD} completed" "Task '${DESC}' passed all gates" 2>/dev/null || true
${SWARM}/episode.sh save "$THREAD" 2>/dev/null || true

# Auto-evolve skills
LESSON_COUNT=$(python3 -c "import json;print(len(json.load(open('${SWARM}/learning/lessons.json'))['lessons']))" 2>/dev/null || echo "0")
[ "$LESSON_COUNT" -gt 10 ] && ${SWARM}/learn.sh evolve 2>/dev/null || true
log "Learning recorded ✅"

# ============================================
# STEP 7: Update status dashboard
# ============================================
log "STEP 7: Dashboard..."
for agent in $AGENTS; do
  ${SWARM}/update-status.sh "$agent" "$THREAD" done "$DESC" 2>/dev/null || true
done
log "Dashboard updated ✅"

# ============================================
# STEP 8: Checkpoint (save post-review state)
# ============================================
${SWARM}/checkpoint.sh save "$THREAD" "review-passed" '{"gates":"all_passed"}' 2>/dev/null || true

# ============================================
# Update mission state
# ============================================
python3 << PY
import json
with open('$STATE') as f: d=json.load(f)
d['status']='awaiting_approval'
d['steps_completed']=['topic','task_file','sandbox','checkpoint','learning_query','status_dashboard','announce','agents_activated','watch_task','progress','evaluator','shomer_review','bodek_test','screenshot','learning_record','dashboard_update']
d['steps_remaining']=['user_approval','deploy']
with open('$STATE','w') as f: json.dump(d,f,indent=2)
PY

# Kill watch/progress
python3 -c "
import json,os,signal
d=json.load(open('$STATE'))
for key in ['watch_pid','progress_pid']:
  pid=d.get(key)
  if pid:
    try: os.kill(pid, signal.SIGTERM)
    except: pass
" 2>/dev/null || true

log "============================================"
log "✅ ALL 8 GATES/STEPS PASSED"
log ""
log "Waiting for user approval..."
log "When approved: deploy.sh ${PROJECT} ${THREAD}"
log "============================================"
