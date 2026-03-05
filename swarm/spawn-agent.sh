#!/bin/bash
# spawn-agent.sh — Generate task text for sub-agent
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [project_dir]

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

cat <<EOF
You are ${AGENT_ID}. 

## Task
${TASK_DESC}

## Rules
1. Work step by step. After each change, TEST it immediately (curl, browser, run tests)
2. If something breaks, fix it before moving on
3. Do NOT use deleteMany({}) on any collection without explicit filter
4. Commit your changes: git add -A && git commit -m "#${THREAD_ID}: description"

## Communication
Report progress to Telegram (your session messages are NOT visible to the user):
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "message"
\`\`\`

${LESSONS:+## Past Lessons
$LESSONS}

## When Done
1. Verify your work: run tests, check with curl, take screenshot if UI
2. Report:
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: <summary>"
/root/.openclaw/workspace/swarm/send.sh or 1 "✅ ${AGENT_ID}-${THREAD_ID} הושלם: <summary>"
bash /root/.openclaw/workspace/swarm/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "<summary>"
\`\`\`

⚠️ An evaluator will check your work after you report done. If it fails, you'll be asked to fix it.
EOF
