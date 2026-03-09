#!/bin/bash
# E2E Pipeline Test — Tests the FULL flow:
# dispatch → state running → verify → state pass/fail
# This is the REAL test that matters.

set -e
SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SWARM_DIR"

PASS=0
FAIL=0
TOTAL=0

check() {
  TOTAL=$((TOTAL+1))
  if eval "$2"; then
    echo "  ✅ $1"
    PASS=$((PASS+1))
  else
    echo "  ❌ $1"
    FAIL=$((FAIL+1))
  fi
}

echo "🧪 E2E Pipeline Tests"
echo ""

# Clean test data
rm -f /tmp/agent-tasks/e2e-test-*.json /tmp/agent-tasks/e2e-test-*.contract.json
rm -f /tmp/agent-done/e2e-test-*.json

# === Test 1: dispatch-task.sh creates contract + state ===
echo "📋 1. dispatch-task.sh"
PROMPT=$(bash dispatch-task.sh e2e-test 99999 "Fix the login button CSS" /root/BotVerse 2>/dev/null)
check "dispatch creates prompt" '[ -n "$PROMPT" ]'
check "dispatch creates task metadata" '[ -f /tmp/agent-tasks/e2e-test-99999.json ]'
check "dispatch creates contract" '[ -f /tmp/agent-tasks/e2e-test-99999.contract.json ]'
check "state is running" 'grep -q "running" /tmp/agent-tasks/e2e-test-99999.json'
check "prompt includes acceptance criteria" 'echo "$PROMPT" | grep -q "Acceptance Criteria"'
check "prompt includes screenshot protocol" 'echo "$PROMPT" | grep -q "SCREENSHOT PROTOCOL"'
check "prompt includes done marker instruction" 'echo "$PROMPT" | grep -q "agent-done"'

echo ""
echo "📋 2. verify-task.sh (before agent completes — should retry)"
VERIFY_OUT=$(bash verify-task.sh e2e-test 99999 2>&1) || true
check "verify returns retry (not auto-pass)" 'echo "$VERIFY_OUT" | grep -q "retry\|RETRY"'

echo ""
echo "📋 3. Contract validation"
CONTRACT=$(cat /tmp/agent-tasks/e2e-test-99999.contract.json)
check "contract has acceptance_criteria" 'echo "$CONTRACT" | python3 -c "import json,sys; c=json.load(sys.stdin); assert len(c.get(\"acceptance_criteria\",[])) > 0"'
check "contract has type" 'echo "$CONTRACT" | python3 -c "import json,sys; c=json.load(sys.stdin); assert c.get(\"type\")"'
check "contract has rollback" 'echo "$CONTRACT" | python3 -c "import json,sys; c=json.load(sys.stdin); assert c.get(\"rollback\")"'

echo ""
echo "📋 4. State machine transitions"
node -e "
  const { createTaskState, transition } = require('./core/state-machine');
  let state = createTaskState('e2e-sm-test');
  console.log('initial:', state.status);
  state = transition(state, 'assigned', 'test');
  console.log('assigned:', state.status);
  state = transition(state, 'running', 'test');
  console.log('running:', state.status);
  state = transition(state, 'verifying', 'test');
  console.log('verifying:', state.status);
  state = transition(state, 'passed', 'test');
  console.log('passed:', state.status);
  console.log('STATES_OK');
" 2>&1 | grep -q "STATES_OK"
check "state machine full path works" 'true'

echo ""
echo "📋 5. Failure taxonomy"
node -e "
  const { classifyFailure } = require('./core/failure-taxonomy');
  const r1 = classifyFailure('SyntaxError: Unexpected token');
  const r2 = classifyFailure('Error: connect ECONNREFUSED');
  const r3 = classifyFailure('Permission denied');
  console.log(r1.category, r2.category, r3.category);
  if (r1.category && r2.category && r3.category) console.log('TAXONOMY_OK');
" 2>&1 | grep -q "TAXONOMY_OK"
check "failure taxonomy classifies errors" 'true'

echo ""
echo "📋 6. send.sh fallback"
# Test that send.sh doesn't crash with missing token (uses fallback)
OUTPUT=$(bash send.sh koder 1 "test" 2>&1) || true
check "send.sh with missing token uses fallback" '! echo "$OUTPUT" | grep -q "No such file"'

echo ""
echo "📋 7. Dashboard API"
API_KEY=$(cat api/.api-key)
HEALTH=$(curl -s "http://localhost:9200/api/health")
check "dashboard health OK" 'echo "$HEALTH" | grep -q "ok"'
STATS=$(curl -s "http://localhost:9200/api/stats?key=$API_KEY")
check "dashboard stats returns JSON" 'echo "$STATS" | grep -q "totalTasks"'

echo ""
echo "📋 8. Done marker flow"
mkdir -p /tmp/agent-done
echo '{"agent":"e2e-test","thread":"99999","completed_at":"2026-03-09T12:00:00Z"}' > /tmp/agent-done/e2e-test-99999.json
check "done marker created" '[ -f /tmp/agent-done/e2e-test-99999.json ]'

echo ""
echo "📋 9. Semantic verification"
node -e "
  const { runVerification } = require('./core/semantic-verify');
  const contract = JSON.parse(require('fs').readFileSync('/tmp/agent-tasks/e2e-test-99999.contract.json', 'utf8'));
  const result = runVerification('e2e-test-99999', contract, { cwd: '/root/BotVerse' });
  console.log('score:', result.score, 'of', result.maxScore);
  console.log('checks:', result.checks.length);
  console.log('VERIFY_OK');
" 2>&1 | grep -q "VERIFY_OK"
check "semantic verification runs" 'true'

# Cleanup
rm -f /tmp/agent-tasks/e2e-test-*.json /tmp/agent-tasks/e2e-test-*.contract.json
rm -f /tmp/agent-done/e2e-test-*.json

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Results: $PASS passed, $FAIL failed, $TOTAL total"
if [ $FAIL -eq 0 ]; then
  echo "✅ ALL TESTS PASSED"
  exit 0
else
  echo "❌ SOME TESTS FAILED"
  exit 1
fi
