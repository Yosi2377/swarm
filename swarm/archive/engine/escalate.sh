#!/bin/bash
# escalate.sh — Escalation handler after max retries
# Usage: escalate.sh <agent_id> <thread_id> <task> <error_history>
set -uo pipefail

[[ "${1:-}" == "--help" || $# -lt 4 ]] && { echo "Usage: escalate.sh <agent_id> <thread_id> <task> <error_history>"; exit 0; }

AGENT="$1"; THREAD="$2"; TASK="$3"; ERRORS="$4"
TASK_DIR="/tmp/engine-tasks"; mkdir -p "$TASK_DIR"
SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ESC_FILE="$TASK_DIR/${AGENT}-${THREAD}-escalation.json"

# Agent fallback mapping
declare -A FALLBACKS=(
  [front]="koder" [koder]="back" [back]="koder" [tzayar]="front"
  [shomer]="koder" [data]="back" [debugger]="koder" [docker]="back"
  [tester]="bodek" [bodek]="tester" [optimizer]="koder" [refactor]="koder"
  [monitor]="docker" [integrator]="back" [worker]="koder" [researcher]="worker"
)

FALLBACK="${FALLBACKS[$AGENT]:-worker}"

# Check error patterns to decide strategy
if echo "$ERRORS" | grep -qiE "timeout|stuck|hang"; then
  DECISION="reassign"
  REASON="Task appears stuck, trying different agent"
  NEW_AGENT="$FALLBACK"
elif echo "$ERRORS" | grep -qiE "complex|multiple|too many"; then
  DECISION="simplify"
  REASON="Task too complex, needs breakdown"
  NEW_AGENT="$AGENT"
else
  # Default: try fallback agent once, then report failure
  DECISION="reassign"
  REASON="Agent $AGENT failed after max retries, escalating to $FALLBACK"
  NEW_AGENT="$FALLBACK"
fi

# Write escalation decision
jq -n --arg agent "$AGENT" --arg new "$NEW_AGENT" --arg thread "$THREAD" \
  --arg task "$TASK" --arg decision "$DECISION" --arg reason "$REASON" \
  --arg ts "$(date -Iseconds)" \
  '{original_agent:$agent, new_agent:$new, thread:$thread, task:$task, decision:$decision, reason:$reason, timestamp:$ts}' \
  > "$ESC_FILE"

echo "[escalate] Decision: $DECISION → $NEW_AGENT ($REASON)"

# Notify General topic
"$SWARM_DIR/send.sh" or 1 "🚨 Escalation: $AGENT failed on task in thread $THREAD
Decision: $DECISION → $NEW_AGENT
Reason: $REASON" 2>/dev/null || true

echo "$ESC_FILE"
