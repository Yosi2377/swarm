#!/bin/bash
# spawn-task.sh — THE orchestrator's main tool
# Spawns agent + attaches smart-eval pipeline
# 
# Usage: source output of this script to get the label/session info
# spawn-task.sh <label> <topic> <task> <eval> [timeout]
#
# Example:
#   bash spawn-task.sh "koder-fix-auth" "8500" \
#     "Fix auth bugs in /root/myproject" \
#     "cd /root/myproject && npm test" \
#     "180"
#
# This script ONLY starts the smart-eval background process.
# The orchestrator must call sessions_spawn SEPARATELY.
# After calling sessions_spawn, call this to attach monitoring.

LABEL="${1:?Usage: spawn-task.sh <label> <topic> <task> <eval> [timeout]}"
TOPIC="${2:-4950}"
TASK="${3:-Agent task}"
EVAL="${4:-Run tests and verify}"
TIMEOUT="${5:-180}"

# Start smart-eval pipeline in background
nohup bash /root/.openclaw/workspace/swarm/smart-eval.sh \
  "${LABEL}" \
  "${TOPIC}" \
  "${EVAL}" \
  "${TIMEOUT}" \
  "${TASK}" \
  > /dev/null 2>&1 &

echo "MONITOR_PID=$!"
echo "$(date -Iseconds) spawn-task: ${LABEL} → topic ${TOPIC} (timeout ${TIMEOUT}s, monitor PID $!)" >> /tmp/spawn-task.log
