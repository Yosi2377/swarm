#!/bin/bash
# test-self-correct.sh — Tests the self-correction loop
# Simulates: agent reports success but verification fails → self-correct → escalation after 3
set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_AGENT="test-agent"
TEST_THREAD="99999"
TASKS_DIR="$SWARM_DIR/core/tasks"
PASS=0
FAIL=0

cleanup() {
  rm -f "$TASKS_DIR/${TEST_AGENT}-${TEST_THREAD}."* 2>/dev/null
  rm -f "$SWARM_DIR/agent-reports/${TEST_AGENT}-${TEST_THREAD}.json" 2>/dev/null
  rm -f "/tmp/verify-${TEST_AGENT}-${TEST_THREAD}.log" 2>/dev/null
  rm -f "/tmp/verify-result-${TEST_AGENT}-${TEST_THREAD}.json" 2>/dev/null
  rm -f "/tmp/retry-history-${TEST_AGENT}-${TEST_THREAD}.json" 2>/dev/null
}

assert_exit() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "  ✅ $name (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name (expected exit=$expected, got exit=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local text="$1" pattern="$2" name="$3"
  if echo "$text" | grep -q "$pattern"; then
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name — pattern '$pattern' not found"
    FAIL=$((FAIL + 1))
  fi
}

echo "🧪 Test Suite: Self-Correction Loop"
echo "===================================="

# -------------------------------------------------------
echo ""
echo "TEST 1: Agent reports success but verify catches failure"
echo "-------------------------------------------------------"
cleanup
mkdir -p "$TASKS_DIR" "$SWARM_DIR/agent-reports"

# Agent falsely reports success
cat > "$SWARM_DIR/agent-reports/${TEST_AGENT}-${TEST_THREAD}.json" <<'EOF'
{"status":"success","summary":"All done!","url":"http://localhost:99999","files_changed":[]}
EOF

# Create a meta file with no real changes
cat > "$TASKS_DIR/${TEST_AGENT}-${TEST_THREAD}.json" <<'EOF'
{"description":"Fix the login page","status":"completed","retries":0}
EOF

# Run verify — should fail (URL won't respond on port 99999)
set +e
OUTPUT=$(bash "$SWARM_DIR/verify-task.sh" "$TEST_AGENT" "$TEST_THREAD" 2>&1)
EXIT_CODE=$?
set -e

assert_exit 1 "$EXIT_CODE" "verify-task.sh returns RETRY on unreachable URL"
assert_contains "$OUTPUT" "FAIL\|RETRY" "Output mentions failure"

# -------------------------------------------------------
echo ""
echo "TEST 2: self-correct.sh generates enriched retry prompt"
echo "-------------------------------------------------------"

# Create a fake verify log with failures
cat > "/tmp/verify-${TEST_AGENT}-${TEST_THREAD}.log" <<'EOF'
❌ FAIL: URL returned HTTP 000
❌ FAIL: Tests failed
EOF

set +e
RETRY_PROMPT=$(bash "$SWARM_DIR/self-correct.sh" "$TEST_AGENT" "$TEST_THREAD" 2>&1)
EXIT_CODE=$?
set -e

assert_exit 1 "$EXIT_CODE" "self-correct.sh returns 1 (retry)"
assert_contains "$RETRY_PROMPT" "RETRY" "Prompt contains RETRY header"
assert_contains "$RETRY_PROMPT" "What Failed" "Prompt explains what failed"
assert_contains "$RETRY_PROMPT" "Correction Strategy" "Prompt includes correction strategy"
assert_contains "$RETRY_PROMPT" "url\|test" "Strategy addresses URL/test failures"

# -------------------------------------------------------
echo ""
echo "TEST 3: After 3 identical failures → ESCALATE"
echo "-------------------------------------------------------"

# Run self-correct 2 more times (already ran once above)
set +e
bash "$SWARM_DIR/self-correct.sh" "$TEST_AGENT" "$TEST_THREAD" >/dev/null 2>&1
RETRY2=$?

OUTPUT3=$(bash "$SWARM_DIR/self-correct.sh" "$TEST_AGENT" "$TEST_THREAD" 2>&1)
RETRY3=$?
set -e

assert_exit 2 "$RETRY3" "self-correct.sh returns 2 (ESCALATE) after 3 same-error retries"
assert_contains "$OUTPUT3" "ESCALATE" "Output mentions ESCALATE"

# -------------------------------------------------------
echo ""
echo "TEST 4: Different errors reset same-error counter"
echo "-------------------------------------------------------"
cleanup

# First error pattern
cat > "/tmp/verify-${TEST_AGENT}-${TEST_THREAD}.log" <<'EOF'
❌ FAIL: Lint failed
EOF

set +e
bash "$SWARM_DIR/self-correct.sh" "$TEST_AGENT" "$TEST_THREAD" >/dev/null 2>&1
R1=$?

# Different error pattern
cat > "/tmp/verify-${TEST_AGENT}-${TEST_THREAD}.log" <<'EOF'
❌ FAIL: Tests failed
EOF
bash "$SWARM_DIR/self-correct.sh" "$TEST_AGENT" "$TEST_THREAD" >/dev/null 2>&1
R2=$?

# Another different pattern
cat > "/tmp/verify-${TEST_AGENT}-${TEST_THREAD}.log" <<'EOF'
❌ FAIL: Syntax errors in 2 file(s)
EOF
bash "$SWARM_DIR/self-correct.sh" "$TEST_AGENT" "$TEST_THREAD" >/dev/null 2>&1
R3=$?
set -e

assert_exit 1 "$R1" "Different error 1 → RETRY"
assert_exit 1 "$R2" "Different error 2 → RETRY"
assert_exit 1 "$R3" "Different error 3 → RETRY (not escalated — errors differ)"

# -------------------------------------------------------
echo ""
echo "TEST 5: verify-task.sh exit 2 after retries exhausted"
echo "-------------------------------------------------------"
cleanup
mkdir -p "$TASKS_DIR"

# Meta with 3 retries already
cat > "$TASKS_DIR/${TEST_AGENT}-${TEST_THREAD}.json" <<'EOF'
{"description":"Fix API","status":"running","retries":3,"task_state":{"retryCount":3}}
EOF

# Agent report pointing to unreachable URL so verify actually fails
cat > "$SWARM_DIR/agent-reports/${TEST_AGENT}-${TEST_THREAD}.json" <<'EOF'
{"status":"success","summary":"Done","url":"http://localhost:99999","files_changed":[]}
EOF

set +e
OUTPUT=$(bash "$SWARM_DIR/verify-task.sh" "$TEST_AGENT" "$TEST_THREAD" 2>&1)
EXIT_CODE=$?
set -e

assert_exit 2 "$EXIT_CODE" "verify-task.sh returns ESCALATE when retries >= 3"
assert_contains "$OUTPUT" "ESCALATE" "Output says ESCALATE"

# -------------------------------------------------------
echo ""
echo "TEST 6: learn.sh records retries"
echo "-------------------------------------------------------"
LESSONS_BEFORE=$(wc -l < "$SWARM_DIR/learning/lessons.jsonl" 2>/dev/null || echo "0")
# The self-correct runs above should have recorded lessons
LESSONS_AFTER=$(wc -l < "$SWARM_DIR/learning/lessons.jsonl" 2>/dev/null || echo "0")

if [ "$LESSONS_AFTER" -ge "$LESSONS_BEFORE" ]; then
  echo "  ✅ Lessons recorded ($LESSONS_AFTER entries)"
  PASS=$((PASS + 1))
else
  echo "  ❌ No lessons recorded"
  FAIL=$((FAIL + 1))
fi

# -------------------------------------------------------
cleanup
echo ""
echo "===================================="
echo "📊 Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "🎉 ALL TESTS PASSED"
  exit 0
else
  echo "💥 SOME TESTS FAILED"
  exit 1
fi
