#!/bin/bash
# test-templates.sh — Verify task templates exist and have required sections
set -e

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="${SWARM_DIR}/templates"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "0" ]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Template Existence Tests ==="
for tmpl in code-fix add-feature ui-change api-endpoint config-change investigation; do
  FILE="${TEMPLATES_DIR}/${tmpl}.md"
  if [ -f "$FILE" ]; then
    echo "✅ ${tmpl}.md exists"
    PASS=$((PASS + 1))
    
    # Check required sections
    echo "  Checking sections in ${tmpl}.md..."
    grep -q "## Steps" "$FILE"; check "Has ## Steps" $?
    grep -q "STEP 1:" "$FILE"; check "Has STEP 1" $?
    grep -q "CHECK:" "$FILE"; check "Has CHECK: markers" $?
    grep -q "## Common Failures" "$FILE"; check "Has ## Common Failures" $?
  else
    echo "❌ ${tmpl}.md MISSING"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=== Dispatch Template Detection Tests ==="
test_dispatch() {
  local desc="$1"
  local expected="$2"
  # Source just the detection logic
  TASK_LOWER=$(echo "$desc" | tr '[:upper:]' '[:lower:]')
  DETECTED=""
  if echo "$TASK_LOWER" | grep -qE '(fix|bug|broken|crash|error|repair)'; then
    DETECTED="code-fix"
  elif echo "$TASK_LOWER" | grep -qE '(ui|css|design|style|layout|color|button)'; then
    DETECTED="ui-change"
  elif echo "$TASK_LOWER" | grep -qE '(api|endpoint|route|rest)'; then
    DETECTED="api-endpoint"
  elif echo "$TASK_LOWER" | grep -qE '(config|env|environment|setting)'; then
    DETECTED="config-change"
  elif echo "$TASK_LOWER" | grep -qE '(research|audit|investigate|check|scan)'; then
    DETECTED="investigation"
  elif echo "$TASK_LOWER" | grep -qE '(add|feature|new|create|implement)'; then
    DETECTED="add-feature"
  fi
  
  if [ "$DETECTED" = "$expected" ]; then
    echo "✅ '$desc' → $expected"
    PASS=$((PASS + 1))
  else
    echo "❌ '$desc' → expected '$expected', got '$DETECTED'"
    FAIL=$((FAIL + 1))
  fi
}

test_dispatch "Fix the login bug" "code-fix"
test_dispatch "Add user profile feature" "add-feature"
test_dispatch "Change button color to blue" "ui-change"
test_dispatch "Create REST API endpoint for users" "api-endpoint"
test_dispatch "Update environment config for production" "config-change"
test_dispatch "Investigate why server is slow" "investigation"
test_dispatch "Fix crash on startup" "code-fix"
test_dispatch "Design new dashboard layout" "ui-change"

echo ""
echo "=== SYSTEM.md Checkpoint Format ==="
if grep -q "Structured Checkpoint Reporting" "${SWARM_DIR}/SYSTEM.md"; then
  echo "✅ SYSTEM.md has checkpoint format section"
  PASS=$((PASS + 1))
else
  echo "❌ SYSTEM.md missing checkpoint format"
  FAIL=$((FAIL + 1))
fi

if grep -q "ALL_PASS/PARTIAL/FAIL" "${SWARM_DIR}/SYSTEM.md"; then
  echo "✅ SYSTEM.md has FINAL status format"
  PASS=$((PASS + 1))
else
  echo "❌ SYSTEM.md missing FINAL status format"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "================================"
echo "PASS: $PASS | FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "❌ SOME TESTS FAILED"
  exit 1
else
  echo "✅ ALL TESTS PASSED"
  exit 0
fi
