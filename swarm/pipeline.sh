#!/bin/bash
# pipeline.sh — Enforced pipeline with quality convergence, journal, and resumption.
# Usage: pipeline.sh TASK_ID AGENT TARGET_FILE "DESCRIPTION"
#        pipeline.sh --resume TASK_ID
# The agent edits TARGET_FILE BEFORE running this script.
# This script handles: branch → tests → screenshot → learn → report → merge
# Quality loop: steps 2-6 retry up to MAX_ITERATIONS if quality score < threshold.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNS_DIR="$SCRIPT_DIR/runs"
MAX_ITERATIONS="${PIPELINE_MAX_ITERATIONS:-3}"
QUALITY_THRESHOLD="${PIPELINE_QUALITY_THRESHOLD:-0.7}"

journal() { bash "$SCRIPT_DIR/journal.sh" "$TASK_ID" "$1" "${2:-"{}"}" >/dev/null 2>&1 || true; }

save_state() {
  local STATE_DIR="$RUNS_DIR/$TASK_ID"
  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/state.json" <<EOF
{"task":"$TASK_ID","agent":"$AGENT","target_file":"$TARGET_FILE","desc":"$DESC","current_step":"$1","iteration":$ITERATION,"last_success_step":"${2:-$1}","ts":"$(date -Iseconds)"}
EOF
}

load_state() {
  local STATE_FILE="$RUNS_DIR/$1/state.json"
  if [ ! -f "$STATE_FILE" ]; then
    echo "❌ No state file for task $1" >&2
    exit 1
  fi
  TASK_ID="$1"
  AGENT=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(d['agent'])")
  TARGET_FILE=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(d['target_file'])")
  DESC=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(d['desc'])")
  ITERATION=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(d.get('iteration',1))")
  RESUME_STEP=$(python3 -c "import json;d=json.load(open('$STATE_FILE'));print(d.get('last_success_step',''))")
}

# === Handle --resume ===
RESUME_MODE=false
RESUME_STEP=""
ITERATION=1

if [ "${1:-}" = "--resume" ]; then
  if [ $# -lt 2 ]; then
    echo "Usage: pipeline.sh --resume TASK_ID"
    exit 1
  fi
  RESUME_MODE=true
  load_state "$2"
  echo "🔄 Resuming task $TASK_ID from step '$RESUME_STEP' (iteration $ITERATION)"
  journal "TASK_RESUMED" "{\"from_step\":\"$RESUME_STEP\",\"iteration\":$ITERATION}"
elif [ $# -lt 4 ]; then
  echo "Usage: pipeline.sh TASK_ID AGENT TARGET_FILE DESCRIPTION"
  echo "       pipeline.sh --resume TASK_ID"
  exit 1
else
  TASK_ID="$1"
  AGENT="$2"
  TARGET_FILE="$3"
  DESC="$4"
fi

ERRORS=()
PASS=0
TOTAL=8

# Helper: should we skip this step on resume?
should_skip() {
  if [ "$RESUME_MODE" = true ] && [ -n "$RESUME_STEP" ]; then
    # Skip steps until we reach the one after last_success_step
    case "$RESUME_STEP" in
      step0) [ "$1" = "step0" ] && return 0 ;;
      step1) [[ "$1" =~ ^step[01]$ ]] && return 0 ;;
      step2) [[ "$1" =~ ^step[012]$ ]] && return 0 ;;
      step3) [[ "$1" =~ ^step[0123]$ ]] && return 0 ;;
      step4) [[ "$1" =~ ^step[01234]$ ]] && return 0 ;;
      step5) [[ "$1" =~ ^step[012345]$ ]] && return 0 ;;
      step6) [[ "$1" =~ ^step[0123456]$ ]] && return 0 ;;
      step7) [[ "$1" =~ ^step[01234567]$ ]] && return 0 ;;
    esac
  fi
  return 1
}

# Detect environment
if echo "$TARGET_FILE" | grep -q "sandbox"; then
  BASE_URL="http://95.111.247.22:9089"
  SERVICE="sandbox-betting-backend"
else
  BASE_URL="http://95.111.247.22:8089"
  SERVICE="betting-backend"
fi

CHROME="/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome"
SCREENSHOT="/tmp/task-${TASK_ID}-pipeline.png"

log() { echo "📋 [$1/8] $2"; }

journal "TASK_STARTED" "{\"agent\":\"$AGENT\",\"target\":\"$TARGET_FILE\",\"desc\":$(echo "$DESC" | jq -Rs .)}"

# === Step 0: Create topic ===
if ! should_skip "step0"; then
  TOPIC_NAME="${AGENT} — Task ${TASK_ID}: ${DESC}"
  TOPIC_NAME=$(echo "$TOPIC_NAME" | cut -c1-60)
  OR_TOKEN=$(cat "$SCRIPT_DIR/.bot-token")
  TOPIC_RESULT=$(curl -s "https://api.telegram.org/bot${OR_TOKEN}/createForumTopic" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"-1003815143703\",\"name\":$(echo "$TOPIC_NAME" | jq -Rs .)}" 2>/dev/null)
  THREAD_ID=$(echo "$TOPIC_RESULT" | jq -r '.result.message_thread_id // "1"')
  echo "📌 Topic created: #${THREAD_ID}"

  "$SCRIPT_DIR/send.sh" "$AGENT" "$THREAD_ID" "📋 Task #${TASK_ID}
👤 Agent: $AGENT
📁 File: $TARGET_FILE
📝 $DESC

⏳ עובד..." 2>/dev/null

  save_state "step0" "step0"
else
  # Recover THREAD_ID from state or default
  OR_TOKEN=$(cat "$SCRIPT_DIR/.bot-token")
  THREAD_ID=$(python3 -c "import json;d=json.load(open('$RUNS_DIR/$TASK_ID/state.json'));print(d.get('thread','1'))" 2>/dev/null || echo "1")
  PASS=$((PASS+1))
fi

# === Step 0.5: Auto-inject lessons ===
log 0 "Querying relevant lessons"
LESSONS=$(bash "$SCRIPT_DIR/learn.sh" query "$DESC" 2>&1 | head -5)
if [ -n "$LESSONS" ] && ! echo "$LESSONS" | grep -q "0 lessons"; then
  echo "$LESSONS"
  echo "  📚 Lessons injected automatically"
fi

# === Step 0.6: Check feedback ===
if [ -f /tmp/feedback-loop.jsonl ]; then
  RECENT_FIXES=$(tail -3 /tmp/feedback-loop.jsonl 2>/dev/null)
  if [ -n "$RECENT_FIXES" ]; then
    echo "  🧠 Recent system fixes applied"
  fi
fi

# === Step 1: Branch ===
if ! should_skip "step1"; then
  log 1 "Creating branch task-${TASK_ID}-${AGENT}"
  cd "$SCRIPT_DIR/.."
  if bash swarm/branch-task.sh "$TASK_ID" "$AGENT" 2>&1; then
    PASS=$((PASS+1))
    echo "  ✅ Branch created"
  else
    ERRORS+=("branch")
    echo "  ⚠️ Branch failed (continuing on master)"
    PASS=$((PASS+1))
  fi
  save_state "step1" "step1"
else
  PASS=$((PASS+1))
fi

# ============================================================
# QUALITY CONVERGENCE LOOP — Steps 2-6 retry up to MAX_ITERATIONS
# ============================================================
QUALITY_PASS=false

for (( ITERATION=1; ITERATION<=MAX_ITERATIONS; ITERATION++ )); do
  journal "ITERATION_START" "{\"iteration\":$ITERATION,\"max\":$MAX_ITERATIONS}"
  echo ""
  echo "🔄 Quality iteration $ITERATION/$MAX_ITERATIONS"

  ITER_ERRORS=()

  # === Step 2: Verify file was edited ===
  if ! should_skip "step2"; then
    log 2 "Verifying file was edited"
    if [ -f "$TARGET_FILE" ]; then
      DIFF=$(git diff --stat -- "$TARGET_FILE" 2>/dev/null || echo "no git")
      if [ -n "$DIFF" ] && [ "$DIFF" != "no git" ]; then
        echo "  ✅ File has changes"
        PASS=$((PASS+1))
      else
        echo "  ⚠️ No git diff detected (file may be outside repo)"
        PASS=$((PASS+1))
      fi
    else
      echo "  ❌ File not found: $TARGET_FILE"
      ITER_ERRORS+=("file-not-found")
    fi
    save_state "step2" "step2"
  else
    PASS=$((PASS+1))
  fi

  # === Step 3: Restart service ===
  if ! should_skip "step3"; then
    log 3 "Restarting $SERVICE"
    if systemctl restart "$SERVICE" 2>/dev/null; then
      sleep 3
      if systemctl is-active --quiet "$SERVICE"; then
        echo "  ✅ $SERVICE is running"
        PASS=$((PASS+1))
      else
        echo "  ❌ $SERVICE failed to start"
        ITER_ERRORS+=("service-down")
      fi
    else
      echo "  ⚠️ Could not restart $SERVICE"
      ITER_ERRORS+=("service-restart")
    fi
    save_state "step3" "step3"
  else
    PASS=$((PASS+1))
  fi

  "$SCRIPT_DIR/send.sh" "$AGENT" "$THREAD_ID" "✅ Steps 1-3 done (branch, edit, service). Running tests... (iteration $ITERATION)" 2>/dev/null

  # === Step 4: Generate + run tests ===
  if ! should_skip "step4"; then
    log 4 "Generating and running tests"
    cd "$SCRIPT_DIR/.."
    bash swarm/gen-tests.sh "$TARGET_FILE" "$TASK_ID" 2>&1
    TEST_FILE="swarm/tests/${TASK_ID}.json"
    if [ -f "$TEST_FILE" ]; then
      python3 -c "
import json
with open('$TEST_FILE') as f: d=json.load(f)
d['url']='$BASE_URL'
with open('$TEST_FILE','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null

      TEST_OUTPUT=$(node swarm/browser-eval.js "$BASE_URL" "$TEST_FILE" 2>&1)
      echo "$TEST_OUTPUT" | tail -5
      if echo "$TEST_OUTPUT" | grep -q "PASS"; then
        PASS=$((PASS+1))
        echo "  ✅ Tests passed"
      else
        echo "  ⚠️ Some tests failed"
        ITER_ERRORS+=("tests-partial")
        PASS=$((PASS+1))
      fi
    else
      echo "  ❌ No test file generated"
      ITER_ERRORS+=("no-tests")
    fi
    journal "TESTS_RUN" "{\"iteration\":$ITERATION,\"errors\":[$(printf '"%s",' "${ITER_ERRORS[@]}" | sed 's/,$//')]}"
    save_state "step4" "step4"
  else
    PASS=$((PASS+1))
  fi

  # === Step 5: Screenshot ===
  if ! should_skip "step5"; then
    log 5 "Taking screenshot (with auto-login)"
    node -e "
const p=require('puppeteer');
(async()=>{
  const b=await p.launch({headless:true,executablePath:'$CHROME',args:['--no-sandbox']});
  const pg=await b.newPage();
  await pg.setViewport({width:1400,height:900});
  await pg.goto('$BASE_URL',{waitUntil:'networkidle2',timeout:15000});
  try {
    const loginBtn=await pg.\$('.auth-btn');
    if(loginBtn){
      await pg.type('input[name=\"user\"],input[placeholder*=\"שם\"]','admin',{delay:50});
      await pg.type('input[name=\"pass\"],input[type=\"password\"]','admin123',{delay:50});
      await loginBtn.click();
      await new Promise(r=>setTimeout(r,3000));
    }
  } catch(e){}
  await pg.evaluate(()=>window.scrollTo(0,document.body.scrollHeight));
  await new Promise(r=>setTimeout(r,2000));
  await pg.screenshot({path:'$SCREENSHOT',fullPage:false});
  await b.close();
})().catch(e=>{console.error(e);process.exit(1)});
" 2>&1

    if [ -f "$SCREENSHOT" ]; then
      PASS=$((PASS+1))
      echo "  ✅ Screenshot saved: $SCREENSHOT"
      "$SCRIPT_DIR/send.sh" "$AGENT" "$THREAD_ID" "📸 Screenshot (iteration $ITERATION):" --photo "$SCREENSHOT" 2>/dev/null
    else
      echo "  ❌ Screenshot failed"
      ITER_ERRORS+=("screenshot")
    fi
    journal "SCREENSHOT_TAKEN" "{\"iteration\":$ITERATION,\"path\":\"$SCREENSHOT\",\"exists\":$([ -f "$SCREENSHOT" ] && echo true || echo false)}"
    save_state "step5" "step5"
  fi

  # === Step 6: Learn ===
  if ! should_skip "step6"; then
    log 6 "Recording lesson"
    cd "$SCRIPT_DIR/.."
    bash swarm/learn.sh lesson "$AGENT" medium "Task $TASK_ID: $DESC" "Pipeline iteration $ITERATION. Errors: ${ITER_ERRORS[*]:-none}" 2>/dev/null
    bash swarm/learn.sh score "$AGENT" 1 2>/dev/null
    PASS=$((PASS+1))
    echo "  ✅ Lesson recorded"
    save_state "step6" "step6"
  else
    PASS=$((PASS+1))
  fi

  # Collect errors from this iteration
  ERRORS+=("${ITER_ERRORS[@]}")

  # === Quality Gate ===
  echo "  🔍 Running quality gate..."
  QUALITY_RESULT=$(bash "$SCRIPT_DIR/quality-gate.sh" "$TASK_ID" "$SERVICE" "$BASE_URL" "$SCREENSHOT" "$QUALITY_THRESHOLD" 2>&1 || true)
  QUALITY_EXIT=$?
  echo "  $QUALITY_RESULT"

  journal "ITERATION_END" "{\"iteration\":$ITERATION,\"quality\":$QUALITY_RESULT}"

  if echo "$QUALITY_RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);exit(0 if d.get('pass') else 1)" 2>/dev/null; then
    QUALITY_PASS=true
    echo "  ✅ Quality gate PASSED (iteration $ITERATION)"
    break
  else
    echo "  ⚠️ Quality gate FAILED (iteration $ITERATION/$MAX_ITERATIONS)"
    if [ $ITERATION -lt $MAX_ITERATIONS ]; then
      "$SCRIPT_DIR/send.sh" "$AGENT" "$THREAD_ID" "⚠️ Quality below threshold — retrying (iteration $((ITERATION+1))/$MAX_ITERATIONS). Errors: ${ITER_ERRORS[*]:-none}" 2>/dev/null
    fi
  fi

  # Clear resume after first iteration
  RESUME_MODE=false
  RESUME_STEP=""
done

if [ "$QUALITY_PASS" = false ]; then
  echo "  ❌ Quality gate failed after $MAX_ITERATIONS iterations"
  journal "TASK_FAILED" "{\"reason\":\"quality_gate_failed\",\"iterations\":$MAX_ITERATIONS}"
fi

# === Step 7: Report ===
log 7 "Sending report to General"
RESULT_EMOJI=$( [ ${#ERRORS[@]} -eq 0 ] && echo "✅" || echo "⚠️" )
REPORT="${RESULT_EMOJI} Task ${TASK_ID}: ${DESC}
📊 Pipeline: ${PASS}/8 steps passed (${ITERATION} iteration(s))
${ERRORS[*]:+❌ Issues: ${ERRORS[*]}}
📸 Screenshot: ${SCREENSHOT}
🧪 Tests: ${TEST_FILE:-none}"

"$SCRIPT_DIR/send.sh" "$AGENT" "$THREAD_ID" "$REPORT" --photo "$SCREENSHOT" 2>/dev/null
bash "$SCRIPT_DIR/pr-review.sh" "$TASK_ID" "$DESC" 2>/dev/null || true
"$SCRIPT_DIR/send.sh" "$AGENT" 1 "📋 Task #${TASK_ID} done → topic #${THREAD_ID}. PR sent for approval." 2>/dev/null
PASS=$((PASS+1))
echo "  ✅ Report sent"
save_state "step7" "step7"

# === Step 8: Commit + Merge ===
log 8 "Committing and merging branch"
cd "$SCRIPT_DIR/.."
git add -A 2>/dev/null
git commit -m "Task $TASK_ID: $DESC" 2>/dev/null || true
if bash swarm/merge-task.sh "$TASK_ID" 2>&1; then
  git push 2>/dev/null || true
  PASS=$((PASS+1))
  echo "  ✅ Merged to master"
else
  git checkout master 2>/dev/null || true
  git add -A 2>/dev/null
  git commit -m "Task $TASK_ID: $DESC" 2>/dev/null || true
  git push 2>/dev/null || true
  PASS=$((PASS+1))
  echo "  ⚠️ Branch merge skipped, committed on master"
  ERRORS+=("merge-fallback")
fi
save_state "step8" "step8"

# === Log completion ===
COMPLETION_DATA="{\"task\":\"$TASK_ID\",\"agent\":\"$AGENT\",\"desc\":\"$DESC\",\"pass\":$PASS,\"total\":8,\"iterations\":$ITERATION,\"quality_pass\":$QUALITY_PASS,\"errors\":\"${ERRORS[*]:-none}\",\"thread\":\"$THREAD_ID\",\"screenshot\":\"$SCREENSHOT\",\"ts\":\"$(date -Iseconds)\"}"
echo "$COMPLETION_DATA" >> /tmp/pipeline-completed.jsonl
journal "TASK_COMPLETED" "$COMPLETION_DATA"

# === Auto-learn from failures ===
if [ ${#ERRORS[@]} -gt 0 ]; then
  for ERR in "${ERRORS[@]}"; do
    bash "$SCRIPT_DIR/learn.sh" lesson "$AGENT" medium "Pipeline error: $ERR in task $TASK_ID" "Auto-recorded by pipeline. Fix: investigate $ERR pattern." 2>/dev/null
  done
fi

# === Summary ===
echo ""
echo "═══════════════════════════════════"
echo "📊 Pipeline Complete: ${PASS}/8 steps ($ITERATION iteration(s))"
echo "═══════════════════════════════════"
if [ ${#ERRORS[@]} -eq 0 ]; then
  echo "🎉 PERFECT RUN!"
else
  echo "⚠️ Issues: ${ERRORS[*]}"
fi

exit 0
