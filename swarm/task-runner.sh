#!/bin/bash
# =============================================================================
# Task Runner — Agent autonomous task execution with self-healing
# Usage: task-runner.sh <project_dir> <task_description> <agent_id> <thread_id>
#
# Flow: Setup → Baseline → Work Loop (max 5) → QA Check → Report
# =============================================================================

set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$1"
TASK_DESC="$2"
AGENT_ID="$3"
THREAD_ID="$4"

# Validate args
if [ -z "$PROJECT_DIR" ] || [ -z "$TASK_DESC" ] || [ -z "$AGENT_ID" ] || [ -z "$THREAD_ID" ]; then
  echo "Usage: $0 <project_dir> <task_description> <agent_id> <thread_id>"
  exit 1
fi

# Generate task ID
TASK_ID="task-${THREAD_ID}-$(date +%s)"
TASK_SHORT="${TASK_ID##task-}"

# Temp files
BASELINE_FILE="/tmp/${TASK_ID}-baseline.json"
REFLECTIONS_FILE="/tmp/${TASK_ID}-reflections.jsonl"
QA_RESULT_FILE="/tmp/${TASK_ID}-qa.json"
STATE_FILE="/tmp/${TASK_ID}-state.json"

# Max iterations
MAX_ITERATIONS=5
MAX_SAME_ERROR=3

# ---- Helpers ----

log() {
  echo "[$(date '+%H:%M:%S')] [${TASK_ID}] $*"
}

send_status() {
  local msg="$1"
  "${SWARM_DIR}/send.sh" "$AGENT_ID" "$THREAD_ID" "$msg" 2>/dev/null || true
}

notify_user() {
  local status="$1"
  local msg="$2"
  "${SWARM_DIR}/notify.sh" "$THREAD_ID" "$status" "$msg" "$AGENT_ID" 2>/dev/null || true
}

save_state() {
  local step="$1"
  local iteration="${2:-0}"
  local status="${3:-running}"
  jq -n \
    --arg task_id "$TASK_ID" \
    --arg step "$step" \
    --argjson iteration "$iteration" \
    --arg status "$status" \
    --arg ts "$(date -Iseconds)" \
    '{task_id:$task_id, step:$step, iteration:$iteration, status:$status, timestamp:$ts}' \
    > "$STATE_FILE"
}

# Detect default branch (main or master)
detect_default_branch() {
  cd "$PROJECT_DIR"
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    echo "master"
  else
    git branch --show-current 2>/dev/null || echo "main"
  fi
}

# Detect test runner
detect_test_command() {
  cd "$PROJECT_DIR"
  if [ -f "package.json" ]; then
    if grep -q '"test"' package.json 2>/dev/null; then
      echo "npm test -- --passWithNoTests 2>&1"
      return
    fi
  fi
  if [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -d "tests" ] && command -v pytest &>/dev/null; then
    echo "pytest --tb=short 2>&1"
    return
  fi
  if [ -f "Makefile" ] && grep -q '^test:' Makefile 2>/dev/null; then
    echo "make test 2>&1"
    return
  fi
  # No tests found
  echo ""
}

# Run tests and return exit code + output
run_tests() {
  local test_cmd
  test_cmd=$(detect_test_command)
  if [ -z "$test_cmd" ]; then
    echo '{"status":"no_tests","output":"No test runner detected","passed":0,"failed":0}'
    return 0
  fi
  cd "$PROJECT_DIR"
  local output exit_code
  output=$(eval "$test_cmd") && exit_code=0 || exit_code=$?
  local status="pass"
  [ "$exit_code" -ne 0 ] && status="fail"
  jq -n \
    --arg status "$status" \
    --arg output "$output" \
    --argjson exit_code "$exit_code" \
    '{status:$status, output:$output, exit_code:$exit_code}'
}

# Extract error signature for dedup
error_signature() {
  local output="$1"
  # Take first error line as signature
  echo "$output" | grep -iE '(error|fail|exception|assert)' | head -1 | sed 's/[0-9]//g' | md5sum | cut -d' ' -f1
}

# =============================================================================
# STEP 1: SETUP — Create branch
# =============================================================================

log "=== STEP 1: SETUP ==="
save_state "setup"

cd "$PROJECT_DIR"
DEFAULT_BRANCH=$(detect_default_branch)
BRANCH_NAME="fix/${AGENT_ID}-${TASK_SHORT}"

# Ensure clean state
git stash --include-untracked 2>/dev/null || true
git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
git pull --ff-only 2>/dev/null || true

# Create work branch
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME" 2>/dev/null || true

send_status "⏳ <b>התחלתי עבודה</b>
📋 משימה: ${TASK_DESC}
🌿 Branch: <code>${BRANCH_NAME}</code>"

log "Branch: $BRANCH_NAME (from $DEFAULT_BRANCH)"

# =============================================================================
# STEP 2: BASELINE — Run existing tests
# =============================================================================

log "=== STEP 2: BASELINE ==="
save_state "baseline"

BASELINE_RESULT=$(run_tests)
echo "$BASELINE_RESULT" > "$BASELINE_FILE"

BASELINE_STATUS=$(echo "$BASELINE_RESULT" | jq -r '.status')
log "Baseline tests: $BASELINE_STATUS"

if [ "$BASELINE_STATUS" = "no_tests" ]; then
  send_status "ℹ️ לא נמצאו טסטים קיימים — ממשיך בלי baseline"
else
  send_status "📊 Baseline: טסטים ${BASELINE_STATUS}"
fi

# =============================================================================
# STEP 3: WORK LOOP — max 5 iterations with self-healing
# =============================================================================

log "=== STEP 3: WORK LOOP ==="
save_state "work_loop" 0

# Initialize tracking
> "$REFLECTIONS_FILE"
ERROR_SIGS=()
ATTEMPT_NUM=0
STRATEGY_CHANGES=0
TASK_PASSED=false

for ((i=1; i<=MAX_ITERATIONS; i++)); do
  ATTEMPT_NUM=$i
  save_state "work_loop" "$i"
  log "--- Iteration $i/$MAX_ITERATIONS ---"
  send_status "🔄 ניסיון ${i}/${MAX_ITERATIONS}..."

  # 3a. Agent works on the task
  # (In real usage, the calling agent executes commands here)
  # This script provides the framework; the agent fills in the work.
  
  # 3b. Run tests
  TEST_RESULT=$(run_tests)
  TEST_STATUS=$(echo "$TEST_RESULT" | jq -r '.status')
  TEST_OUTPUT=$(echo "$TEST_RESULT" | jq -r '.output')

  # 3c. If tests pass → move to QA
  if [ "$TEST_STATUS" = "pass" ] || [ "$TEST_STATUS" = "no_tests" ]; then
    log "Tests passed on iteration $i"
    notify_user "progress" "✅ טסטים עברו בניסיון $i — עובר ל-QA"
    TASK_PASSED=true
    break
  fi

  # 3d. Tests failed → reflection
  log "Tests failed, running reflection..."
  REFLECTION=$("${SWARM_DIR}/reflect.sh" "$TEST_OUTPUT" "$i" "$REFLECTIONS_FILE" 2>/dev/null || echo '{"what_failed":"unknown","why":"reflection failed","next_strategy":"retry","avoid":"same approach"}')
  echo "$REFLECTION" >> "$REFLECTIONS_FILE"

  # 3e. Check for repeated errors
  CURRENT_SIG=$(error_signature "$TEST_OUTPUT")
  SIG_COUNT=0
  for sig in "${ERROR_SIGS[@]:-}"; do
    [ "$sig" = "$CURRENT_SIG" ] && ((SIG_COUNT++)) || true
  done
  ERROR_SIGS+=("$CURRENT_SIG")

  if [ "$SIG_COUNT" -ge "$((MAX_SAME_ERROR - 1))" ]; then
    log "Same error $MAX_SAME_ERROR times — switching strategy!"
    send_status "⚠️ אותה שגיאה ${MAX_SAME_ERROR} פעמים — מחליף אסטרטגיה"
    
    # Stash current work, create new branch
    ((STRATEGY_CHANGES++))
    git stash --include-untracked 2>/dev/null || true
    NEW_BRANCH="${BRANCH_NAME}-v${STRATEGY_CHANGES}"
    git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
    git checkout -b "$NEW_BRANCH" 2>/dev/null || true
    BRANCH_NAME="$NEW_BRANCH"
    
    # Reset error tracking
    ERROR_SIGS=()
  fi

  # 3f. Update thread with status
  NEXT_STRATEGY=$(echo "$REFLECTION" | jq -r '.next_strategy // "retry"')
  send_status "❌ ניסיון ${i} נכשל
🔍 אסטרטגיה הבאה: ${NEXT_STRATEGY}"
done

# =============================================================================
# STEP 4: QA CHECK
# =============================================================================

log "=== STEP 4: QA CHECK ==="
save_state "qa_check"

if [ "$TASK_PASSED" = true ]; then
  # 4a. Run full QA guard
  QA_RESULT=$("${SWARM_DIR}/qa-guard.sh" "$PROJECT_DIR" "$BASELINE_FILE" 2>/dev/null || echo '{"status":"error","details":"qa-guard failed"}')
  echo "$QA_RESULT" > "$QA_RESULT_FILE"
  QA_STATUS=$(echo "$QA_RESULT" | jq -r '.status')

  # 4b. Check git diff
  cd "$PROJECT_DIR"
  CHANGED_FILES=$(git diff --name-only "$DEFAULT_BRANCH" 2>/dev/null | wc -l)
  DIFF_STAT=$(git diff --stat "$DEFAULT_BRANCH" 2>/dev/null || echo "no diff available")

  # 4c. Too many files changed?
  if [ "$CHANGED_FILES" -gt 10 ]; then
    send_status "⚠️ <b>התראה:</b> ${CHANGED_FILES} קבצים השתנו — יותר מ-10!
בדוק שהשינויים רלוונטיים."
    log "WARNING: $CHANGED_FILES files changed (>10)"
  fi

  if [ "$QA_STATUS" = "regression" ]; then
    send_status "🚨 <b>REGRESSION!</b> טסטים שעברו קודם עכשיו נכשלים.
$(echo "$QA_RESULT" | jq -r '.details // ""')"
    TASK_PASSED=false
  fi
else
  log "Task did not pass after $MAX_ITERATIONS iterations"
  QA_STATUS="skipped"
  DIFF_STAT="N/A — task did not pass"
  CHANGED_FILES=0
fi

# =============================================================================
# STEP 5: REPORT
# =============================================================================

log "=== STEP 5: REPORT ==="
save_state "report" "$ATTEMPT_NUM" "$([ "$TASK_PASSED" = true ] && echo 'done' || echo 'failed')"

cd "$PROJECT_DIR"
DIFF_STAT=$(git diff --stat "$DEFAULT_BRANCH" 2>/dev/null || echo "no changes")

if [ "$TASK_PASSED" = true ]; then
  send_status "✅ <b>משימה הושלמה!</b>

📋 <b>משימה:</b> ${TASK_DESC}
🔄 <b>ניסיונות:</b> ${ATTEMPT_NUM}
🌿 <b>Branch:</b> <code>${BRANCH_NAME}</code>
📁 <b>קבצים שהשתנו:</b> ${CHANGED_FILES}

<b>שינויים:</b>
<pre>${DIFF_STAT}</pre>

<b>QA:</b> ${QA_STATUS}
🔀 מוכן למרג' מ-<code>${BRANCH_NAME}</code>"
  notify_user "success" "✅ משימה הושלמה — ${TASK_DESC} — branch ${BRANCH_NAME}"
else
  # Collect reflections summary
  REFLECTIONS_SUMMARY=$(tail -3 "$REFLECTIONS_FILE" 2>/dev/null | jq -r '.what_failed // "unknown"' 2>/dev/null | head -3 || echo "no reflections")

  send_status "❌ <b>משימה לא הושלמה</b>

📋 <b>משימה:</b> ${TASK_DESC}
🔄 <b>ניסיונות:</b> ${ATTEMPT_NUM}/${MAX_ITERATIONS}
🔀 <b>החלפות אסטרטגיה:</b> ${STRATEGY_CHANGES}

<b>כישלונות אחרונים:</b>
<pre>${REFLECTIONS_SUMMARY}</pre>

צריך התערבות ידנית."
  notify_user "failed" "❌ משימה נכשלה — ${TASK_DESC} — אחרי ${ATTEMPT_NUM} ניסיונות"
fi

# Final state
save_state "complete" "$ATTEMPT_NUM" "$([ "$TASK_PASSED" = true ] && echo 'success' || echo 'failed')"

# ---- Auto-Learn ----
log "=== AUTO-LEARN ==="
if [ "$TASK_PASSED" = true ]; then
  # Save success lesson
  "${SWARM_DIR}/learn.sh" lesson "$AGENT_ID" "normal" 1.0 \
    "Completed: ${TASK_DESC}" \
    "Task solved in ${ATTEMPT_NUM} attempts, ${STRATEGY_CHANGES} strategy changes" 2>/dev/null || true
  # Score the agent
  "${SWARM_DIR}/learn.sh" score "$AGENT_ID" "$TASK_ID" \
    "$([ $ATTEMPT_NUM -le 2 ] && echo 'pass' || echo 'partial')" \
    "Attempts: ${ATTEMPT_NUM}, Strategy changes: ${STRATEGY_CHANGES}" 2>/dev/null || true
else
  # Save failure lesson  
  LAST_ERROR=$(tail -1 "$REFLECTIONS_FILE" 2>/dev/null | jq -r '.what_failed // "unknown"' 2>/dev/null || echo "unknown")
  "${SWARM_DIR}/learn.sh" lesson "$AGENT_ID" "important" 0.8 \
    "Failed: ${TASK_DESC}" \
    "Could not solve after ${MAX_ITERATIONS} attempts. Last error: ${LAST_ERROR}" 2>/dev/null || true
  "${SWARM_DIR}/learn.sh" score "$AGENT_ID" "$TASK_ID" "fail" \
    "Failed after ${ATTEMPT_NUM} attempts" 2>/dev/null || true
fi

# ---- Pieces LTM ----
"${SWARM_DIR}/pieces-realtime.sh" "agent:${AGENT_ID}" \
  "Task $([ "$TASK_PASSED" = true ] && echo 'completed' || echo 'failed'): ${TASK_DESC} (${ATTEMPT_NUM} attempts)" 2>/dev/null &

log "=== DONE (passed=$TASK_PASSED, attempts=$ATTEMPT_NUM) ==="

# Exit code
[ "$TASK_PASSED" = true ] && exit 0 || exit 1
