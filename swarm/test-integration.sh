#!/bin/bash
# test-integration.sh — Integration tests for pretrain, route, and hooks
set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
TOTAL=0

test_result() {
  TOTAL=$((TOTAL + 1))
  if [ "$1" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $2"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $2"
  fi
}

echo "=== Integration Tests ==="
echo ""

# --- Test 1: pretrain.sh generates valid JSON ---
echo "📦 Test: pretrain.sh"
TEST_PROJECT="/tmp/test-pretrain-project"
mkdir -p "$TEST_PROJECT/src"
cat > "$TEST_PROJECT/package.json" <<'EOF'
{"name":"test-project","scripts":{"test":"jest","build":"tsc"},"dependencies":{"express":"4.18","mongoose":"7.0"}}
EOF
echo "const app = require('express')(); // TODO: add auth" > "$TEST_PROJECT/src/index.js"
echo "app.get('/api', (req,res) => res.json({}));" >> "$TEST_PROJECT/src/index.js"

KNOWLEDGE_FILE=$(bash "$SWARM_DIR/engine/pretrain.sh" "$TEST_PROJECT" --force 2>/dev/null)
test_result $? "pretrain.sh exits 0"

# Validate JSON
jq . "$KNOWLEDGE_FILE" >/dev/null 2>&1
test_result $? "pretrain.sh output is valid JSON"

# Check fields
jq -e '.stack | length > 0' "$KNOWLEDGE_FILE" >/dev/null 2>&1
test_result $? "pretrain detects stack (node, express, mongodb)"

jq -e '.test_command == "jest"' "$KNOWLEDGE_FILE" >/dev/null 2>&1
test_result $? "pretrain detects test command"

jq -e '.known_issues | length > 0' "$KNOWLEDGE_FILE" >/dev/null 2>&1
test_result $? "pretrain finds TODO comments"

# Test caching (should return immediately)
KNOWLEDGE_FILE2=$(bash "$SWARM_DIR/engine/pretrain.sh" "$TEST_PROJECT" 2>/dev/null)
test_result $? "pretrain.sh caching works (no --force)"
[ "$KNOWLEDGE_FILE" = "$KNOWLEDGE_FILE2" ]
test_result $? "pretrain returns same file path on cache hit"

rm -rf "$TEST_PROJECT"
echo ""

# --- Test 2: route.sh picks correct agents ---
echo "🧭 Test: route.sh"

AGENT=$(bash "$SWARM_DIR/engine/route.sh" "fix a bug in the login page" 2>/dev/null)
[ "$AGENT" = "koder" ]
test_result $? "route 'fix bug' → koder (got: $AGENT)"

AGENT=$(bash "$SWARM_DIR/engine/route.sh" "scan for security vulnerabilities" 2>/dev/null)
[ "$AGENT" = "shomer" ]
test_result $? "route 'security vulnerabilities' → shomer (got: $AGENT)"

AGENT=$(bash "$SWARM_DIR/engine/route.sh" "design a new logo" 2>/dev/null)
[ "$AGENT" = "tzayar" ]
test_result $? "route 'design logo' → tzayar (got: $AGENT)"

AGENT=$(bash "$SWARM_DIR/engine/route.sh" "add unit tests for the API" 2>/dev/null)
[ "$AGENT" = "tester" ]
test_result $? "route 'unit tests' → tester (got: $AGENT)"

AGENT=$(bash "$SWARM_DIR/engine/route.sh" "deploy with docker compose" 2>/dev/null)
[ "$AGENT" = "docker" ]
test_result $? "route 'docker compose' → docker (got: $AGENT)"

AGENT=$(bash "$SWARM_DIR/engine/route.sh" "research best practices for caching" 2>/dev/null)
[ "$AGENT" = "researcher" ]
test_result $? "route 'research best practices' → researcher (got: $AGENT)"

echo ""

# --- Test 3: hooks.sh pre/post run without errors ---
echo "🪝 Test: hooks.sh"

PRE_OUTPUT=$(bash "$SWARM_DIR/engine/hooks.sh" pre "koder" "test-999" "fix a bug in login" 2>/dev/null)
test_result $? "hooks.sh pre exits 0"

POST_OUTPUT=$(bash "$SWARM_DIR/engine/hooks.sh" post "koder" "test-999" "success" 2>/dev/null)
POST_EXIT=$?
test_result $POST_EXIT "hooks.sh post exits 0 or returns status"

echo ""

# --- Test 4: Full flow ---
echo "🔄 Test: Full flow (route → pretrain → dispatch)"

TEST_PROJECT2="/tmp/test-flow-project"
mkdir -p "$TEST_PROJECT2"
echo '{"name":"flow-test","scripts":{"test":"echo ok","build":"echo ok"}}' > "$TEST_PROJECT2/package.json"

# Route
AGENT=$(bash "$SWARM_DIR/engine/route.sh" "implement a new API endpoint" 2>/dev/null)
test_result $? "flow: route selects agent ($AGENT)"

# Pretrain
KFILE=$(bash "$SWARM_DIR/engine/pretrain.sh" "$TEST_PROJECT2" --force 2>/dev/null)
test_result $? "flow: pretrain generates knowledge"

# Dispatch (auto mode)
DISPATCH_OUTPUT=$(bash "$SWARM_DIR/dispatch-task.sh" "auto" "test-flow" "implement a new API endpoint" "$TEST_PROJECT2" 2>/dev/null)
[ -n "$DISPATCH_OUTPUT" ]
test_result $? "flow: dispatch-task.sh with auto routing produces output"

rm -rf "$TEST_PROJECT2"
echo ""

# --- Summary ---
echo "================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "================================"

[ $FAIL -eq 0 ] && exit 0 || exit 1
