#!/bin/bash
# dispatch.sh v2 — Full automated dispatch pipeline
# One command does everything: topic → task → send → metadata → queue
#
# Usage: dispatch.sh <agent_id> "task description" [--url URL] [--test "cmd"] [--project /path] [--expect "text"] [--scroll-to "selector"]
#
# Example:
#   dispatch.sh koder "Fix login bug on /admin" --url https://botverse.dev/admin --test "npm test" --project /root/BotVerse
#   dispatch.sh shomer "Run security audit" --url https://botverse.dev --expect "All tests passed"

set -euo pipefail

AGENT_ID="${1:?Usage: dispatch.sh <agent_id> \"task description\" [--url URL] [--test \"cmd\"] [--project /path] [--expect \"text\"]}"
TASK_DESC="${2:?Missing task description}"
shift 2

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
SWARM_DIR="$(cd "${RUNNER_DIR}/.." && pwd)"

# Parse optional args
URL="" TEST_CMD="" PROJECT_DIR="" EXPECT="" SCROLL_TO="" TOPIC_NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)       URL="$2"; shift 2 ;;
        --test)      TEST_CMD="$2"; shift 2 ;;
        --project)   PROJECT_DIR="$2"; shift 2 ;;
        --expect)    EXPECT="$2"; shift 2 ;;
        --scroll-to) SCROLL_TO="$2"; shift 2 ;;
        --name)      TOPIC_NAME="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Agent emoji map
declare -A EMOJI_MAP=(
    [koder]="⚙️" [shomer]="🔒" [tzayar]="🎨" [researcher]="🔍"
    [bodek]="🧪" [worker]="🤖" [data]="📊" [debugger]="🐛"
    [docker]="🐳" [front]="🖥️" [back]="⚡" [tester]="🧪"
    [refactor]="♻️" [monitor]="📡" [optimizer]="🚀" [integrator]="🔗"
)
EMOJI="${EMOJI_MAP[$AGENT_ID]:-🤖}"
TOPIC_NAME="${TOPIC_NAME:-${EMOJI} $(echo "$TASK_DESC" | head -c 60)}"

# Step 1: Create topic
echo "📌 Creating topic..."
THREAD=$(bash "${SWARM_DIR}/create-topic.sh" "${TOPIC_NAME}" "" "${AGENT_ID}" 2>/dev/null)
if [ -z "$THREAD" ] || [ "$THREAD" = "null" ]; then
    echo "❌ Failed to create topic" >&2
    exit 1
fi
echo "   → Topic #${THREAD}"

# Step 2: Generate task text with lessons
echo "📝 Generating task text..."
TASK_TEXT=$(bash "${SWARM_DIR}/spawn-agent.sh" "${AGENT_ID}" "${THREAD}" "${TASK_DESC}" "${TEST_CMD}" "${PROJECT_DIR}")

# Step 3: Send task to topic
echo "📤 Sending task to topic..."
bash "${SWARM_DIR}/send.sh" "${AGENT_ID}" "${THREAD}" "📋 משימה: ${TASK_DESC}" >/dev/null 2>&1

# Step 4: Write metadata
TASK_ID="${AGENT_ID}-${THREAD}"
META_DIR="/tmp/agent-tasks"
mkdir -p "$META_DIR"
cat > "${META_DIR}/${TASK_ID}.json" <<METAEOF
{
    "task_id": "${TASK_ID}",
    "agent_id": "${AGENT_ID}",
    "thread_id": "${THREAD}",
    "task_desc": $(echo "$TASK_DESC" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
    "url": "${URL}",
    "test_cmd": "${TEST_CMD}",
    "project_dir": "${PROJECT_DIR}",
    "expect": "${EXPECT}",
    "scroll_to": "${SCROLL_TO}",
    "dispatched_at": "$(date -Iseconds)",
    "status": "queued",
    "retries": 0
}
METAEOF

# Step 5: Write queue file for watcher
QUEUE_DIR="/tmp/dispatch-queue"
mkdir -p "$QUEUE_DIR"
cat > "${QUEUE_DIR}/${TASK_ID}.json" <<QEOF
{
    "task_id": "${TASK_ID}",
    "agent_id": "${AGENT_ID}",
    "thread_id": "${THREAD}",
    "task_text": $(echo "$TASK_TEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
    "label": "${TASK_ID}",
    "url": "${URL}",
    "test_cmd": "${TEST_CMD}",
    "project_dir": "${PROJECT_DIR}",
    "expect": "${EXPECT}",
    "queued_at": "$(date -Iseconds)"
}
QEOF

echo ""
echo "✅ Dispatched: ${TASK_ID}"
echo "   Thread: ${THREAD}"
echo "   Queue:  ${QUEUE_DIR}/${TASK_ID}.json"
echo "   Meta:   ${META_DIR}/${TASK_ID}.json"
echo ""
echo "THREAD=${THREAD}"
echo "TASK_ID=${TASK_ID}"
echo "LABEL=${TASK_ID}"
echo "---TASK_TEXT---"
echo "${TASK_TEXT}"
