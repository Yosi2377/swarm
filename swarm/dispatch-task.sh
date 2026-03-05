#!/bin/bash
# dispatch-task.sh — Complete task dispatch pipeline
# Usage: dispatch-task.sh <agent_id> <task_name> <task_description> [test_command] [project_dir]
#
# This script:
# 1. Creates a topic
# 2. Sends the task via send.sh
# 3. Generates spawn text via spawn-agent.sh
# 4. Outputs everything needed for sessions_spawn
#
# The orchestrator (Or) must then:
# 1. Call sessions_spawn with the output
# 2. When agent completes → run verify-task.sh
# 3. Only report to Yossi after verify passes

AGENT_ID="${1:?Usage: dispatch-task.sh <agent_id> <task_name> <task_description> [test_command] [project_dir]}"
TASK_NAME="${2:?Missing task_name}"
TASK_DESC="${3:?Missing task_description}"
TEST_CMD="${4:-}"
PROJECT_DIR="${5:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

# Step 1: Create topic
THREAD=$(bash "${SWARM_DIR}/create-topic.sh" "${TASK_NAME}" "" "${AGENT_ID}" 2>/dev/null)
if [ -z "$THREAD" ] || [ "$THREAD" = "null" ]; then
    echo "ERROR: Failed to create topic" >&2
    exit 1
fi

# Step 2: Send task message to topic
bash "${SWARM_DIR}/send.sh" "${AGENT_ID}" "${THREAD}" "📋 משימה: ${TASK_DESC}" >/dev/null 2>&1

# Step 3: Generate spawn text
TASK_TEXT=$(bash "${SWARM_DIR}/spawn-agent.sh" "${AGENT_ID}" "${THREAD}" "${TASK_DESC}")

# Step 4: Save metadata for verification later
META_DIR="/tmp/agent-tasks"
mkdir -p "$META_DIR"
cat > "${META_DIR}/${AGENT_ID}-${THREAD}.json" <<METAEOF
{
    "agent_id": "${AGENT_ID}",
    "thread_id": "${THREAD}",
    "task_name": "${TASK_NAME}",
    "task_desc": "${TASK_DESC}",
    "test_cmd": "${TEST_CMD}",
    "project_dir": "${PROJECT_DIR}",
    "dispatched_at": "$(date -Iseconds)",
    "status": "running"
}
METAEOF

# Output for orchestrator
echo "THREAD=${THREAD}"
echo "LABEL=${AGENT_ID}-${THREAD}"
echo "---TASK_TEXT---"
echo "${TASK_TEXT}"
