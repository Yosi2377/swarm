#!/bin/bash
# verify.sh — Run all checks and return PASS/FAIL
# Usage: verify.sh <checks_file>    (one check command per line)
#    or: echo "checks" | verify.sh -
# Exit: 0=PASS, 1=FAIL
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS_FILE="${1:?Usage: verify.sh <checks_file>}"

if [ "$CHECKS_FILE" = "-" ]; then
  CHECKS_FILE=$(mktemp)
  cat > "$CHECKS_FILE"
  trap "rm -f $CHECKS_FILE" EXIT
fi

if [ ! -f "$CHECKS_FILE" ]; then
  echo "❌ FAIL: checks file not found: $CHECKS_FILE" >&2
  exit 1
fi

TOTAL=0
PASSED=0
FAILED=0
DETAILS=""

while IFS= read -r line; do
  [ -z "$line" ] && continue
  [[ "$line" =~ ^# ]] && continue
  TOTAL=$((TOTAL + 1))

  # Parse: first word is check type, rest are args
  CHECK_TYPE=$(echo "$line" | awk '{print $1}')
  ARGS=$(echo "$line" | cut -d' ' -f2-)

  OUTPUT=$(bash "$ENGINE_DIR/check.sh" $CHECK_TYPE $ARGS 2>&1) && RC=0 || RC=$?

  if [ $RC -eq 0 ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
  DETAILS="${DETAILS}${OUTPUT}\n"
done < "$CHECKS_FILE"

echo -e "$DETAILS"
echo "━━━━━━━━━━━━━━━━━━"
echo "Results: $PASSED/$TOTAL passed, $FAILED failed"

if [ $FAILED -eq 0 ] && [ $TOTAL -gt 0 ]; then
  echo "✅ PASS"
  exit 0
else
  echo "❌ FAIL"
  exit 1
fi
