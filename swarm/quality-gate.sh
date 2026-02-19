#!/bin/bash
# quality-gate.sh — Score task quality and return pass/fail
# Usage: quality-gate.sh <task-id> <service-name> <base-url> <screenshot-path> [threshold]
# Output: JSON with score and pass/fail, exit 0=pass, exit 1=fail

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TASK_ID="$1"
SERVICE="$2"
BASE_URL="$3"
SCREENSHOT="$4"
THRESHOLD="${5:-0.7}"

# Dimension scores (0.0 or 1.0 each)
SCORE_SERVICE=0
SCORE_TESTS=0
SCORE_SCREENSHOT=0
SCORE_NO_ERRORS=0

# 1. Service running?
if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
  SCORE_SERVICE=1
fi

# 2. Tests passed? Check recent test output
TEST_FILE="$SCRIPT_DIR/tests/${TASK_ID}.json"
if [ -f "$TEST_FILE" ]; then
  TEST_OUT=$(node "$SCRIPT_DIR/browser-eval.js" "$BASE_URL" "$TEST_FILE" 2>&1 || true)
  if echo "$TEST_OUT" | grep -q "PASS"; then
    SCORE_TESTS=1
  fi
else
  # No test file = neutral, give half credit
  SCORE_TESTS=0.5
fi

# 3. Screenshot exists and non-empty?
if [ -f "$SCREENSHOT" ] && [ -s "$SCREENSHOT" ]; then
  SIZE=$(stat -c%s "$SCREENSHOT" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 5000 ]; then
    SCORE_SCREENSHOT=1
  fi
fi

# 4. No JS errors? Quick curl check for server response
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  SCORE_NO_ERRORS=1
fi

# Calculate weighted average
TOTAL=$(echo "$SCORE_SERVICE $SCORE_TESTS $SCORE_SCREENSHOT $SCORE_NO_ERRORS" | \
  awk '{printf "%.2f", ($1*0.3 + $2*0.3 + $3*0.2 + $4*0.2)}')

PASS=$(echo "$TOTAL $THRESHOLD" | awk '{print ($1 >= $2) ? "true" : "false"}')

RESULT="{\"task\":\"$TASK_ID\",\"score\":$TOTAL,\"threshold\":$THRESHOLD,\"pass\":$PASS,\"dimensions\":{\"service_running\":$SCORE_SERVICE,\"tests_pass\":$SCORE_TESTS,\"screenshot_valid\":$SCORE_SCREENSHOT,\"no_errors\":$SCORE_NO_ERRORS},\"ts\":\"$(date -Iseconds)\"}"

echo "$RESULT"

# Log to journal
bash "$SCRIPT_DIR/journal.sh" "$TASK_ID" "QUALITY_SCORED" "$RESULT" >/dev/null 2>&1 || true

if [ "$PASS" = "true" ]; then
  exit 0
else
  exit 1
fi
