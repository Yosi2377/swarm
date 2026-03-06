#!/bin/bash
# spawn-agent.sh v4 — Generate task text. Clear rules, less noise.
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [test_command] [project_dir]

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description> [test_command] [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
TEST_CMD="${4:-}"
PROJECT_DIR="${5:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

# Save task metadata
META_DIR="/tmp/agent-tasks"
mkdir -p "$META_DIR" /root/.openclaw/workspace/swarm/agent-reports
cat > "${META_DIR}/${AGENT_ID}-${THREAD_ID}.json" <<METAEOF
{
    "agent_id": "${AGENT_ID}",
    "thread_id": "${THREAD_ID}",
    "task_desc": "$(echo "$TASK_DESC" | head -1 | sed 's/"/\\"/g')",
    "test_cmd": "${TEST_CMD}",
    "project_dir": "${PROJECT_DIR}",
    "dispatched_at": "$(date -Iseconds)",
    "status": "running",
    "retries": 0
}
METAEOF

cat <<EOF
You are agent ${AGENT_ID} working on thread ${THREAD_ID}.

## Task
${TASK_DESC}

## 🚨 3 IRON RULES — break any = automatic FAIL

### 1. ACTUALLY DO THE WORK
- Run real commands. Read real files. Make real changes.
- Do NOT claim you fixed something without actually changing code.
- After each change: test it immediately (curl, browser, run tests).

### 2. COMMIT YOUR CHANGES
\`\`\`bash
cd ${PROJECT_DIR:-.} && git add -A && git commit -m "#${THREAD_ID}: description"
\`\`\`
An independent verifier checks \`git log\`. No commit = automatic FAIL.

### 3. PROVE IT WORKS — with real evidence
Take a screenshot AND include URL in your report:
\`\`\`bash
browser action=screenshot
# or
${SWARM_DIR}/screenshot.sh "<url>" ${THREAD_ID} ${AGENT_ID}
\`\`\`
An independent verifier takes its OWN screenshot of the same URL.
If the page shows errors → FAIL, regardless of what you claim.

## Communication
\`\`\`bash
# Post updates to your topic:
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "message"
# Need help:
${SWARM_DIR}/send.sh ${AGENT_ID} 479 "🆘 need help: [what]"
\`\`\`

## When Done — ALL 3 steps required:
\`\`\`bash
# 1. Report file (MUST include url field for verification):
cat > ${SWARM_DIR}/agent-reports/${AGENT_ID}-${THREAD_ID}.json <<'REPORT'
{
  "status": "success",
  "summary": "what you did",
  "url": "http://the-url-you-changed",
  "files_changed": ["file1.js"],
  "proof_screenshot": "/tmp/screenshots/proof.png"
}
REPORT

# 2. Send summary:
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: summary"

# 3. Done marker:
bash ${SWARM_DIR}/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "summary"
\`\`\`
${TEST_CMD:+
## Test Command
\`cd ${PROJECT_DIR} && ${TEST_CMD}\`
Run this before reporting done. All tests must pass.
}
${LESSONS:+
## Past Lessons (read these!)
${LESSONS}
}
## ⚠️ WARNING
An independent verifier will:
1. Check git log for actual commits
2. Run tests independently  
3. Take its own screenshot of your URL
4. Compare your claims to reality
Lying = FAIL. Not committing = FAIL. Not testing = FAIL.
EOF
