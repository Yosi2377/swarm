#!/bin/bash
# watch-subagent.sh — Watch a specific subagent and notify when done
# Usage: watch-subagent.sh <label> <thread_id> <description> [poll_seconds]
# Runs in background, checks if subagent is still active, notifies on completion

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="${1:?Usage: watch-subagent.sh <label> <thread_id> <description>}"
THREAD="${2:?Missing thread_id}"
DESC="${3:?Missing description}"
POLL="${4:-30}"

echo "👁️ Watching subagent '$LABEL' for thread $THREAD (poll ${POLL}s)"

while true; do
  sleep "$POLL"
  
  # Check if any process with this label is still running
  # We look for the label in active openclaw sessions
  ACTIVE=$(ps aux | grep -c "subagent.*$LABEL" 2>/dev/null || echo "0")
  
  # Also check the marker file approach
  if [ -f "/tmp/subagent-done-${LABEL}" ]; then
    EXIT_CODE=$(cat "/tmp/subagent-done-${LABEL}" 2>/dev/null || echo "0")
    rm -f "/tmp/subagent-done-${LABEL}"
    
    if [ "$EXIT_CODE" = "0" ]; then
      "${SWARM_DIR}/notify.sh" "$THREAD" success "✅ סוכן סיים: ${DESC}"
    else
      "${SWARM_DIR}/notify.sh" "$THREAD" failed "❌ סוכן נכשל: ${DESC}"
    fi
    echo "$(date +%H:%M:%S) → Subagent '$LABEL' done (exit=$EXIT_CODE)"
    exit 0
  fi
done
