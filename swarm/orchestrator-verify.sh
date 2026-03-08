#!/bin/bash
# orchestrator-verify.sh — Runs semantic verification, decides retry/pass/escalate
# Usage: orchestrator-verify.sh <agent_id> <thread_id> [project_dir]
# Output: JSON { action: 'pass'|'retry'|'escalate', ... }

AGENT_ID="${1:?Usage: orchestrator-verify.sh <agent_id> <thread_id> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
PROJECT_DIR="${3:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

node -e "
const bridge = require('${SWARM_DIR}/core/orchestrator-bridge');
const context = process.argv[3] ? { cwd: process.argv[3] } : {};
const result = bridge.onAgentDone(process.argv[1], process.argv[2], context);
console.log(JSON.stringify(result, null, 2));
" "$AGENT_ID" "$THREAD_ID" "$PROJECT_DIR"
