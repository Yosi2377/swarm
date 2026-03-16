#!/bin/bash
# on-agent-done.sh v4 — Routes to SwarmClaw evaluator
# Usage: on-agent-done.sh <agent_id> <thread_id> [test_cmd] [project_dir]

AGENT_ID="${1:?Usage: on-agent-done.sh <agent_id> <thread_id>}"
THREAD_ID="${2:?Missing thread_id}"

# Detect project from project_dir or default to botverse
PROJECT_DIR="${4:-}"
PROJECT="botverse"
if echo "$PROJECT_DIR" | grep -qi "betting"; then PROJECT="betting"; fi
if echo "$PROJECT_DIR" | grep -qi "poker"; then PROJECT="poker"; fi

exec /root/SwarmClaw/core/run-evaluator.sh "$AGENT_ID" "$THREAD_ID" "$PROJECT"
