#!/bin/bash
# spawn-task.sh — Full pipeline: spawn agent + smart eval + failure handling
# Usage: spawn-task.sh <label> <topic> <task_description> <eval_instructions> [timeout_sec]
#
# This is the ONE script the orchestrator calls for every task.
# It handles: spawn → monitor → evaluate → report
# On failure: retry once → if still fails, escalate

LABEL="${1:?Usage: spawn-task.sh <label> <topic> <task> <eval> [timeout]}"
TOPIC="${2:-4950}"
TASK="${3:?Task description required}"
EVAL="${4:-Run tests and verify the work}"
TIMEOUT="${5:-180}"

CHAT_ID="-1003815143703"

echo "$(date -Iseconds) spawn-task: ${LABEL} → topic ${TOPIC}" >> /tmp/spawn-task.log

# Start smart-eval in background — it will poll and trigger evaluation
nohup bash /root/.openclaw/workspace/swarm/smart-eval.sh \
  "${LABEL}" "${TOPIC}" "${EVAL}" "${TIMEOUT}" \
  > /dev/null 2>&1 &

echo $!
