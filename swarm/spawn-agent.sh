#!/bin/bash
# spawn-agent.sh v3 — Generate task text with strict enforcement
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
You are ${AGENT_ID}. 

## Task
${TASK_DESC}

## Process (MANDATORY — follow in order)
1. **Understand** — Read the task. Read relevant code.
2. **Plan** — Decide what to change. List the files.
3. **Implement** — One change at a time.
4. **Test** — After EACH change, run tests immediately.${TEST_CMD:+
   \`cd ${PROJECT_DIR} && ${TEST_CMD}\`}
5. **Verify** — ALL tests must pass before reporting done.

## Rules
- After each change, TEST immediately
- Do NOT use deleteMany({}) without explicit filter
- Do NOT fabricate credentials/tokens — ask the orchestrator if needed
- If STUCK: ask in Agent Chat (thread 479) and WAIT

## Communication
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "message"
\`\`\`
Need help:
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} 479 "🆘 צריך עזרה: [what you need]"
\`\`\`

${LESSONS:+## Past Lessons
$LESSONS}

## ⛔ MANDATORY BEFORE REPORTING DONE — ALL 4 STEPS REQUIRED
## ⚠️ IF YOU SKIP ANY STEP — THE TASK IS NOT DONE. PERIOD.

### Step 1: VERIFY IT ACTUALLY WORKS (MOST IMPORTANT!)
Before saying "done", you MUST prove it works with REAL evidence:
\`\`\`bash
# For web tasks — screenshot the ACTUAL result:
${SWARM_DIR}/screenshot.sh "<THE_URL_YOU_CHANGED>" ${THREAD_ID} ${AGENT_ID} "proof"

# For API tasks — show the actual curl output:
curl -s <the_endpoint> | head -20

# For code tasks — run the actual test and show output:
cd ${PROJECT_DIR:-.} && <test_command>
\`\`\`
**LOOK AT YOUR SCREENSHOT/OUTPUT. Does it actually show what was requested?**
- If the screenshot shows a login page instead of the feature → NOT DONE
- If the curl returns an error → NOT DONE  
- If tests fail → NOT DONE
**DO NOT proceed to Step 2 until you have REAL proof it works.**

### Step 2: Git Commit
\`\`\`bash
cd ${PROJECT_DIR:-.} && git add -A && git commit -m "#${THREAD_ID}: brief description"
\`\`\`

### Step 3: Structured Report with EVIDENCE
\`\`\`bash
mkdir -p /root/.openclaw/workspace/swarm/agent-reports
cat > /root/.openclaw/workspace/swarm/agent-reports/${AGENT_ID}-${THREAD_ID}.json <<'DONE'
{
  "status": "success",
  "summary": "Brief description of what was done",
  "files_changed": ["file1.js", "file2.js"],
  "tests_run": true,
  "tests_passed": true,
  "test_count": {"passed": 0, "failed": 0, "total": 0},
  "proof_screenshot": "/tmp/screenshots/<filename>.png",
  "proof_description": "Screenshot shows X working correctly"
}
DONE
\`\`\`
**proof_screenshot is REQUIRED. No screenshot = automatic FAIL.**

### Step 4: Send Screenshot FIRST, Then Summary
\`\`\`bash
# FIRST — send screenshot to topic
PROOF=\$(ls /tmp/screenshots/${AGENT_ID}-${THREAD_ID}*.png 2>/dev/null | tail -1)
TOKEN=\$(cat ${SWARM_DIR}/.${AGENT_ID}-token)
curl -s -X POST "https://api.telegram.org/bot\${TOKEN}/sendPhoto" \\
  -F "chat_id=-1003815143703" -F "message_thread_id=${THREAD_ID}" \\
  -F "photo=@\${PROOF}" -F "caption=📸 Proof — task completed"

# THEN — text summary
${SWARM_DIR}/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: <summary>"
${SWARM_DIR}/send.sh or 1 "✅ ${AGENT_ID}-${THREAD_ID} הושלם: <summary>"
\`\`\`

## ⚠️ WARNING
The orchestrator will INDEPENDENTLY run the tests and check for:
1. All tests pass (run independently, not trusting your claim)
2. Structured report exists at /root/.openclaw/workspace/swarm/agent-reports/${AGENT_ID}-${THREAD_ID}.json
3. All changes are git committed (git status --porcelain must be clean)

**If ANY check fails → you will be asked to fix. Lying about results = failure.**

## 🚨 REMEMBER
The #1 reason agents fail: they SAY "done" without CHECKING it works.
- ALWAYS test your own work before reporting
- ALWAYS take a screenshot as proof
- ALWAYS look at the screenshot — does it show what was asked?
- If you're not 100% sure it works — IT DOESN'T. Keep working.
EOF
