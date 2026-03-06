#!/bin/bash
# dispatch.sh — Simple wrapper to dispatch a task through the agent runner
# Usage: dispatch.sh <agent_id> "<task>" [--url URL] [--test "cmd"] [--project /path]
#
# This is what the orchestrator (Or) should use instead of raw sessions_spawn

AGENT_ID="${1:?Usage: dispatch.sh <agent_id> \"task\" [--url URL] [--test \"cmd\"] [--project /path]}"
TASK="${2:?Missing task description}"
shift 2

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse optional args
URL=""
TEST_CMD=""
PROJECT_DIR=""
THREAD_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --url) URL="$2"; shift 2 ;;
        --test) TEST_CMD="$2"; shift 2 ;;
        --project) PROJECT_DIR="$2"; shift 2 ;;
        --thread) THREAD_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Build config JSON
CONFIG=$(cat <<EOF
{
    "agentId": "${AGENT_ID}",
    "taskDesc": $(echo "$TASK" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
    "url": "${URL}",
    "testCmd": "${TEST_CMD}",
    "projectDir": "${PROJECT_DIR}",
    "threadId": "${THREAD_ID}"
}
EOF
)

CONFIG_FILE="/tmp/runner-config-${AGENT_ID}-$$.json"
echo "$CONFIG" > "$CONFIG_FILE"

echo "🚀 Dispatching to ${AGENT_ID}..."
echo "📋 Task: ${TASK:0:80}"
echo "🌐 URL: ${URL:-none}"
echo "🧪 Test: ${TEST_CMD:-none}"
echo ""

node "${RUNNER_DIR}/agent-runner.js" "$CONFIG_FILE"
EXIT=$?

rm -f "$CONFIG_FILE"
exit $EXIT
