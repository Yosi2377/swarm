#!/bin/bash
# orchestrator-dispatch.sh — Creates contract, validates, saves state, generates enriched prompt
# Usage: orchestrator-dispatch.sh <agent_id> <thread_id> <task_description> [project_dir]
# Output: the full agent prompt (to pass to sessions_spawn)

AGENT_ID="${1:?Usage: orchestrator-dispatch.sh <agent_id> <thread_id> <task_description> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

node -e "
const bridge = require('${SWARM_DIR}/core/orchestrator-bridge');
const projectConfig = process.argv[4] ? { basePath: process.argv[4] } : {};
const result = bridge.prepareTask(process.argv[1], process.argv[2], process.argv[3], projectConfig);
if (result.errors) {
  console.error(JSON.stringify({ errors: result.errors }));
  process.exit(1);
}
// Output the enriched prompt section (append to spawn-agent.sh output)
console.log(result.agentPrompt);
" "$TASK_DESC" "$AGENT_ID" "$THREAD_ID" "$PROJECT_DIR"
