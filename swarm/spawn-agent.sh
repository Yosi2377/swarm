#!/bin/bash
# spawn-agent.sh — Generate task text for sub-agent
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>
# Output: prints task text to stdout

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

cat <<EOF
You are ${AGENT_ID}. Read /root/.openclaw/workspace/swarm/SYSTEM.md for instructions.

**Task:** ${TASK_DESC}

**Topic:** ${THREAD_ID}
**Report via:** \`/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "message"\`

${LESSONS}

**When DONE:**
1. Verify your work actually works (tests, curl, browser — whatever fits)
2. Send: \`/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: [summary]"\`
3. Send: \`/root/.openclaw/workspace/swarm/send.sh or 1 "✅ ${AGENT_ID}-${THREAD_ID} הושלם: [summary]"\`
4. Run: \`bash /root/.openclaw/workspace/swarm/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "summary"\`
EOF
