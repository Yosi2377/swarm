#!/bin/bash
# spawn-agent.sh v5 — Uses SwarmClaw project config for context
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [test_command] [project_dir]

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
TEST_CMD="${4:-}"
PROJECT_DIR="${5:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
SC_DIR="/root/SwarmClaw"

# Detect project
PROJECT="botverse"
if echo "$PROJECT_DIR" | grep -qi "betting"; then PROJECT="betting"; fi
if echo "$PROJECT_DIR" | grep -qi "poker"; then PROJECT="poker"; fi

# Try to load project config for context
PROJECT_BLOCK=""
CONFIG_FILE="${SC_DIR}/config/${PROJECT}.yaml"
if [ -f "$CONFIG_FILE" ]; then
    PROJECT_BLOCK=$(cd "$SC_DIR" && node -e "
const { loadProject, agentContext } = require('./core/project-config');
const config = loadProject('${CONFIG_FILE}');
const ctx = agentContext(config);
console.log(ctx.prompt_block);
" 2>/dev/null)
fi

# Inject lessons
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

# Save task metadata
META_DIR="/tmp/agent-tasks"
mkdir -p "$META_DIR" "${SWARM_DIR}/agent-reports"
cat > "${META_DIR}/${AGENT_ID}-${THREAD_ID}.json" <<METAEOF
{
    "agent_id": "${AGENT_ID}",
    "thread_id": "${THREAD_ID}",
    "task_desc": "$(echo "$TASK_DESC" | head -1 | sed 's/"/\\"/g')",
    "test_cmd": "${TEST_CMD}",
    "project_dir": "${PROJECT_DIR}",
    "project": "${PROJECT}",
    "dispatched_at": "$(date -Iseconds)",
    "status": "running",
    "retries": 0
}
METAEOF

cat <<EOF
You are agent ${AGENT_ID} working on thread ${THREAD_ID}.

${PROJECT_BLOCK}

## Task
${TASK_DESC}

## How to Work
1. **Understand** — Read the relevant code first
2. **Plan** — Post your plan to the topic before coding
3. **Do** — Make changes. Work in sandbox if available.
4. **Test** — After EVERY change, verify it works:${TEST_CMD:+
   \`cd ${PROJECT_DIR} && ${TEST_CMD}\`}
   curl the URL, check browser, read logs.
   If broken → fix → test again. Loop until it works.
5. **Commit** — \`cd ${PROJECT_DIR:-.} && git add -A && git commit -m "#${THREAD_ID}: description"\`

## Communication
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "message"
\`\`\`

## When Done — ALL 3 steps:
\`\`\`bash
# 1. Report (MUST include 'url'):
cat > ${SWARM_DIR}/agent-reports/${AGENT_ID}-${THREAD_ID}.json <<'REPORT'
{
  "status": "success",
  "summary": "what you did",
  "url": "THE_URL_TO_VERIFY",
  "files_changed": ["file1.js"]
}
REPORT

# 2. Notify:
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: summary"
${SWARM_DIR}/send.sh or 1 "✅ ${AGENT_ID}-${THREAD_ID} הושלם: summary"

# 3. Done marker:
bash ${SWARM_DIR}/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "summary"
\`\`\`

${LESSONS:+## Past Lessons
${LESSONS}}

## ⚠️ Verification
An independent SwarmClaw evaluator will check:
- git log for real commits (code tasks)
- Tests independently
- Your URL independently
- LLM judgment: "did this actually solve the task?"
Lying = FAIL. Not testing = FAIL. Not committing = FAIL.
EOF
