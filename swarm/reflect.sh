#!/bin/bash
# =============================================================================
# Reflect — Generate structured reflection after a failed attempt
# Usage: reflect.sh <error_output> <attempt_number> <previous_reflections_file>
# Output: JSON with what_failed, why, next_strategy, avoid
# =============================================================================

set -uo pipefail

ERROR_OUTPUT="$1"
ATTEMPT_NUM="${2:-1}"
PREV_REFLECTIONS_FILE="${3:-/dev/null}"

if [ -z "$ERROR_OUTPUT" ]; then
  echo '{"what_failed":"unknown","why":"no error output provided","next_strategy":"retry with more context","avoid":"blind retry"}'
  exit 0
fi

# ---- Parse error patterns ----

# Truncate error to manageable size
ERROR_TRUNC=$(echo "$ERROR_OUTPUT" | tail -100)

# Detect common error categories
CATEGORY="unknown"
WHAT_FAILED=""
WHY=""
NEXT_STRATEGY=""
AVOID=""

if echo "$ERROR_TRUNC" | grep -qi "syntaxerror\|SyntaxError\|unexpected token\|parsing error"; then
  CATEGORY="syntax"
  WHAT_FAILED="Syntax error in code"
  WHY="Invalid syntax — likely a typo, missing bracket, or wrong language construct"
  NEXT_STRATEGY="Review the exact line mentioned in error, fix syntax carefully"
  AVOID="Blind editing without reading the error line number"

elif echo "$ERROR_TRUNC" | grep -qi "modulenotfounderror\|cannot find module\|no module named\|import error"; then
  CATEGORY="import"
  WHAT_FAILED="Missing module or import error"
  WHY="Required dependency not installed, or wrong import path"
  NEXT_STRATEGY="Check if module exists: npm ls / pip list. Install if missing, fix path if wrong"
  AVOID="Adding code that uses uninstalled packages"

elif echo "$ERROR_TRUNC" | grep -qi "typeerror\|is not a function\|undefined is not\|cannot read prop"; then
  CATEGORY="type"
  WHAT_FAILED="Type error — wrong data type or undefined value"
  WHY="Variable is undefined/null, or calling method on wrong type"
  NEXT_STRATEGY="Add null checks, verify variable types, trace data flow"
  AVOID="Assuming variables exist without checking"

elif echo "$ERROR_TRUNC" | grep -qi "assertionerror\|assert\|expected.*to\|toBe\|toEqual"; then
  CATEGORY="assertion"
  WHAT_FAILED="Test assertion failed — output doesn't match expected"
  WHY="Logic error: the code runs but produces wrong result"
  NEXT_STRATEGY="Compare expected vs actual, trace the logic step by step"
  AVOID="Changing test expectations instead of fixing the code"

elif echo "$ERROR_TRUNC" | grep -qi "timeout\|timed out\|ETIMEDOUT\|ECONNREFUSED"; then
  CATEGORY="network"
  WHAT_FAILED="Network/connection error"
  WHY="Service not running, wrong port, or network issue"
  NEXT_STRATEGY="Check if target service is running, verify URLs and ports"
  AVOID="Retrying without checking service status"

elif echo "$ERROR_TRUNC" | grep -qi "permission denied\|EACCES\|EPERM"; then
  CATEGORY="permission"
  WHAT_FAILED="Permission denied"
  WHY="File/directory permissions block access"
  NEXT_STRATEGY="Check file ownership and permissions, use appropriate user"
  AVOID="Using chmod 777 as a fix"

else
  CATEGORY="unknown"
  WHAT_FAILED="Test/build failure — see error output"
  WHY="Could not auto-categorize the error"
  NEXT_STRATEGY="Read error output carefully, search web if unfamiliar"
  AVOID="Repeating the same approach without understanding the error"
fi

# ---- Check previous reflections for patterns ----

PREV_COUNT=0
REPEATED=false
if [ -f "$PREV_REFLECTIONS_FILE" ] && [ -s "$PREV_REFLECTIONS_FILE" ]; then
  PREV_COUNT=$(wc -l < "$PREV_REFLECTIONS_FILE")
  # Check if same category appeared before
  if grep -q "\"category\":\"${CATEGORY}\"" "$PREV_REFLECTIONS_FILE" 2>/dev/null; then
    REPEATED=true
    NEXT_STRATEGY="DIFFERENT APPROACH NEEDED: Same error category (${CATEGORY}) seen before. Try a fundamentally different solution path."
    AVOID="Any approach similar to previous attempts — the pattern is failing"
  fi
fi

# ---- Output JSON ----

jq -n \
  --arg what_failed "$WHAT_FAILED" \
  --arg why "$WHY" \
  --arg next_strategy "$NEXT_STRATEGY" \
  --arg avoid "$AVOID" \
  --arg category "$CATEGORY" \
  --argjson attempt "$ATTEMPT_NUM" \
  --argjson prev_attempts "$PREV_COUNT" \
  --argjson repeated "$REPEATED" \
  --arg error_excerpt "$(echo "$ERROR_TRUNC" | head -10)" \
  --arg ts "$(date -Iseconds)" \
  '{
    what_failed: $what_failed,
    why: $why,
    next_strategy: $next_strategy,
    avoid: $avoid,
    category: $category,
    attempt: $attempt,
    previous_attempts: $prev_attempts,
    repeated_pattern: $repeated,
    error_excerpt: $error_excerpt,
    timestamp: $ts
  }'
