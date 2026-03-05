#!/bin/bash
# spawn-agent.sh — Generate task text for sub-agent (v2)
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [test_command] [project_dir]

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [test_command] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
TEST_CMD="${4:-}"
PROJECT_DIR="${5:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

# Save task metadata for verification
META_DIR="/tmp/agent-tasks"
mkdir -p "$META_DIR"
cat > "${META_DIR}/${AGENT_ID}-${THREAD_ID}.json" <<METAEOF
{
    "agent_id": "${AGENT_ID}",
    "thread_id": "${THREAD_ID}",
    "task_desc": "$(echo "$TASK_DESC" | head -1 | sed 's/"/\\"/g')",
    "test_cmd": "${TEST_CMD}",
    "project_dir": "${PROJECT_DIR}",
    "dispatched_at": "$(date -Iseconds)",
    "status": "running"
}
METAEOF

cat <<EOF
You are ${AGENT_ID}. 

## Task
${TASK_DESC}

## Process (MANDATORY — follow in order)
1. **Understand** — Read the task. Read relevant code. Understand what's expected.
2. **Plan** — Decide what to change. List the files.
3. **Implement** — Make changes one at a time.
4. **Test** — After EACH change, run tests immediately.${TEST_CMD:+
   Test command: \`${TEST_CMD}\`}${PROJECT_DIR:+
   Project dir: \`${PROJECT_DIR}\`}
5. **Verify** — Run ALL tests one final time before reporting done.

## Rules
1. After each change, TEST immediately — don't batch changes
2. Do NOT use deleteMany({}) without explicit filter
3. Do NOT fabricate credentials/tokens — if you need one, ask the orchestrator
4. Commit: git add -A && git commit -m "#${THREAD_ID}: description"

## Communication
Report to your topic:
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "message"
\`\`\`

If you're STUCK or need information you don't have:
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} 479 "🆘 צריך עזרה: [what you need]"
\`\`\`
Then WAIT for the orchestrator to respond before continuing.

${LESSONS:+## Past Lessons
$LESSONS}

## Completion Report (MANDATORY FORMAT)
When done, create this file FIRST:
\`\`\`bash
cat > /tmp/agent-done/${AGENT_ID}-${THREAD_ID}.json <<'DONE'
{
  "status": "success",
  "summary": "What was done (1-2 sentences)",
  "files_changed": ["file1.js", "file2.js"],
  "tests_run": true,
  "tests_passed": true,
  "test_count": {"passed": 0, "failed": 0, "total": 0}
}
DONE
\`\`\`

Then report:
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: <summary>"
${SWARM_DIR}/send.sh or 1 "✅ ${AGENT_ID}-${THREAD_ID} הושלם: <summary>"
\`\`\`

⚠️ The orchestrator will INDEPENDENTLY verify your work after you report done.
⚠️ If verification fails, you will be asked to fix. Lying about test results = automatic failure.
EOF
