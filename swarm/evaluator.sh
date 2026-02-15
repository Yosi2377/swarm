#!/bin/bash
# evaluator.sh <thread_id> <agent_id> [project]
# Runs tests, takes screenshots, checks git diff, sends results
set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
THREAD="${1:?Usage: evaluator.sh <thread_id> <agent_id> [project]}"
AGENT="${2:?Missing agent_id}"
PROJECT="${3:-auto}"
CHAT_ID="-1003815143703"

# Resolve bot token (use orchestrator token)
TOKEN=$(cat "$SWARM_DIR/.or-token" 2>/dev/null || cat "$SWARM_DIR/.bot-token" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "❌ No bot token found"
  exit 1
fi

send_msg() {
  local thread="$1"
  local msg="$2"
  curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$CHAT_ID\",\"message_thread_id\":$thread,\"text\":\"$msg\",\"parse_mode\":\"HTML\"}" >/dev/null 2>&1 || true
}

echo "🔍 Evaluating thread $THREAD for agent $AGENT..."

# 0. Check for uncommitted changes in workspace
cd /root/.openclaw/workspace
UNCOMMITTED=$(git status --porcelain | wc -l)
if [ "$UNCOMMITTED" -gt 0 ]; then
  echo "❌ FAIL: Uncommitted changes in workspace: $UNCOMMITTED files"
  send_msg "$THREAD" "❌ <b>Evaluator FAILED</b> — Thread $THREAD

Uncommitted changes in workspace: $UNCOMMITTED files
Run: git add -A && git commit before reporting done."
  echo "Uncommitted changes: $UNCOMMITTED files" > "/tmp/retry-feedback-${THREAD}.txt"
  exit 1
fi

# 1. Detect project if auto
if [ "$PROJECT" = "auto" ]; then
  if [ -f "$SWARM_DIR/tasks/${THREAD}.md" ]; then
    task_content=$(cat "$SWARM_DIR/tasks/${THREAD}.md")
    if echo "$task_content" | grep -qi "betting\|הימור\|8089"; then
      PROJECT="betting"
    elif echo "$task_content" | grep -qi "poker\|פוקר"; then
      PROJECT="poker"
    elif echo "$task_content" | grep -qi "dashboard\|דאשבורד\|8090"; then
      PROJECT="dashboard"
    fi
  fi
fi

# 2. Run tests
echo "📋 Running tests (project: $PROJECT)..."
TEST_OUTPUT=$("$SWARM_DIR/test-runner.sh" "$PROJECT" "$THREAD" 2>&1) || true
TEST_RC=$?
echo "$TEST_OUTPUT"

# 3. Check git diff (sandbox vs production)
GIT_SUMMARY=""
declare -A PROJECT_PATHS=(
  ["betting"]="/root/BettingPlatform"
  ["poker"]="/root/TexasPokerGame"
  ["dashboard"]="/root/.openclaw/workspace/swarm/dashboard"
)

if [[ -n "${PROJECT_PATHS[$PROJECT]+x}" ]]; then
  SANDBOX_PATH="/root/sandbox/${PROJECT_PATHS[$PROJECT]##*/}"
  PROD_PATH="${PROJECT_PATHS[$PROJECT]}"
else
  SANDBOX_PATH=""
  PROD_PATH=""
fi

if [ -n "$PROD_PATH" ] && [ -d "$SANDBOX_PATH" ] && [ -d "$PROD_PATH" ]; then
  DIFF_STAT=$(diff -rq "$SANDBOX_PATH" "$PROD_PATH" --exclude=node_modules --exclude=.git --exclude=dist 2>/dev/null | head -20) || true
  if [ -n "$DIFF_STAT" ]; then
    FILE_COUNT=$(echo "$DIFF_STAT" | wc -l)
    GIT_SUMMARY="📁 $FILE_COUNT files differ between sandbox and production"
  else
    GIT_SUMMARY="📁 No differences (sandbox = production)"
  fi
fi

# 4. Take screenshots if possible
SCREENSHOTS=()
# Determine URL based on project
declare -A PROJECT_URLS=(
  ["betting"]="http://95.111.247.22:9089"
  ["poker"]="https://zozopoker.duckdns.org"
  ["dashboard"]="http://localhost:8090"
)
if [[ -n "${PROJECT_URLS[$PROJECT]+x}" ]]; then
  URL="${PROJECT_URLS[$PROJECT]}"
else
  URL=""
fi

if [ -n "$URL" ] && command -v node >/dev/null 2>&1; then
  for viewport in "1920x1080:desktop" "768x1024:tablet" "375x812:mobile"; do
    IFS=':' read -r size label <<< "$viewport"
    IFS='x' read -r w h <<< "$size"
    SHOT="/tmp/eval-${THREAD}-${label}.png"
    node -e "
const puppeteer = require('puppeteer');
(async () => {
  const b = await puppeteer.launch({headless:true, executablePath:'/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome', args:['--no-sandbox']});
  const p = await b.newPage();
  await p.setViewport({width:$w, height:$h});
  try { await p.goto('$URL', {waitUntil:'networkidle2', timeout:10000}); } catch(e) {}
  await new Promise(r=>setTimeout(r,2000));
  await p.screenshot({path:'$SHOT', fullPage:false});
  await b.close();
})();" 2>/dev/null && SCREENSHOTS+=("$SHOT")
  done
fi

# 4b. Save eval output to history
mkdir -p "$SWARM_DIR/learning"
echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] THREAD=$THREAD AGENT=$AGENT RC=$TEST_RC" >> "$SWARM_DIR/learning/eval-history.log"
echo "$TEST_OUTPUT" >> "$SWARM_DIR/learning/eval-history.log"
echo "---" >> "$SWARM_DIR/learning/eval-history.log"
echo "$TEST_OUTPUT" > "/tmp/eval-errors-${THREAD}.txt"

# 5. Determine result and send to Telegram
if [ $TEST_RC -eq 0 ]; then
  RESULT="PASS"
  EMOJI="✅"
  
  # Send success to General (topic 1)
  MSG="$EMOJI <b>Evaluator PASSED</b> — Thread $THREAD ($AGENT)
$TEST_OUTPUT
$GIT_SUMMARY

🟢 מחכה לאישור deploy"
  send_msg 1 "$MSG"
  
  # Send screenshots to General
  for shot in "${SCREENSHOTS[@]}"; do
    label=$(basename "$shot" .png | sed "s/eval-${THREAD}-//")
    curl -sf -F "chat_id=$CHAT_ID" -F "message_thread_id=1" \
      -F "photo=@$shot" -F "caption=📸 $label — Thread $THREAD" \
      "https://api.telegram.org/bot${TOKEN}/sendPhoto" >/dev/null 2>&1 || true
  done
  
  echo ""
  echo "✅ EVALUATION PASSED"
  exit 0
else
  RESULT="FAIL"
  
  # Send failure to agent's topic
  FAIL_MSG="❌ <b>Evaluator FAILED</b> — Thread $THREAD

$TEST_OUTPUT

תקן את השגיאות ודווח שוב."
  send_msg "$THREAD" "$FAIL_MSG"
  
  # Write feedback file for retry.sh
  echo "$TEST_OUTPUT" > "/tmp/retry-feedback-${THREAD}.txt"
  
  echo ""
  echo "❌ EVALUATION FAILED"
  exit 1
fi
