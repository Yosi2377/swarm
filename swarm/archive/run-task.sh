#!/bin/bash
# run-task.sh — Wrapper that GUARANTEES notify is sent
# Usage: run-task.sh <thread_id> <agent_id> <command...>
# This wraps ANY agent command and ensures notify on start + finish

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
THREAD="${1:?Usage: run-task.sh <thread_id> <agent_id> <command...>}"
AGENT="${2:?Missing agent_id}"
shift 2

TASK_DESC="$*"
START_TIME=$(date +%s)

# ALWAYS notify start
"${SWARM_DIR}/notify.sh" "$THREAD" progress "⏳ ${AGENT} מתחיל: ${TASK_DESC}" "$AGENT"

# Run the actual command
"$@"
EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

# ALWAYS notify finish
if [ "$EXIT_CODE" -eq 0 ]; then
  "${SWARM_DIR}/notify.sh" "$THREAD" success "✅ ${AGENT} סיים (${DURATION}s): ${TASK_DESC}" "$AGENT"
else
  "${SWARM_DIR}/notify.sh" "$THREAD" failed "❌ ${AGENT} נכשל (exit ${EXIT_CODE}, ${DURATION}s): ${TASK_DESC}" "$AGENT"
fi

# Auto-learn
"${SWARM_DIR}/learn.sh" lesson "$AGENT" "normal" 1.0 \
  "Task: ${TASK_DESC}" \
  "Exit: ${EXIT_CODE}, Duration: ${DURATION}s" 2>/dev/null || true

"${SWARM_DIR}/pieces-realtime.sh" "agent:${AGENT}" \
  "Task $([ $EXIT_CODE -eq 0 ] && echo done || echo failed): ${TASK_DESC}" 2>/dev/null &

exit $EXIT_CODE
