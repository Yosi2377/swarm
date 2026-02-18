#!/bin/bash
# self-heal.sh — Self-healing wrapper for critical commands
# Usage: self-heal.sh MAX_RETRIES COMMAND...

set -uo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: self-heal.sh MAX_RETRIES COMMAND..."
  exit 1
fi

MAX_RETRIES="$1"
shift
COMMAND=("$@")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
  attempt=$((attempt + 1))
  echo "⚙️ Attempt $attempt/$MAX_RETRIES: ${COMMAND[*]}"
  rc=0
  "${COMMAND[@]}" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "✅ Success on attempt $attempt"
    exit 0
  fi
  echo "❌ Failed attempt $attempt/$MAX_RETRIES (exit code: $rc)"
  if [ "$attempt" -lt "$MAX_RETRIES" ]; then
    sleep 5
  fi
done

# All retries exhausted
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOGFILE="/tmp/heal-${TIMESTAMP}.log"

{
  echo "🔴 Self-heal FAILED"
  echo "Command: ${COMMAND[*]}"
  echo "Max retries: $MAX_RETRIES"
  echo "Timestamp: $(date -Iseconds)"
  echo "Exit after $MAX_RETRIES attempts"
} > "$LOGFILE"

echo "📝 Log saved to $LOGFILE"

# Alert orchestrator
"$SCRIPT_DIR/send.sh" or 1 "🔴 Self-heal failed after $MAX_RETRIES attempts: ${COMMAND[*]}" 2>/dev/null || true

# Record lesson
"$SCRIPT_DIR/learn.sh" lesson or critical "self-heal failed: ${COMMAND[*]}" "Command failed $MAX_RETRIES times. Log: $LOGFILE" 2>/dev/null || true

exit 1
