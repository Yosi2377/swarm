#!/bin/bash
# spawn-agent.sh — Generate task text for sub-agent
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>
# Output: prints task text to stdout
# Generic — works with any project

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

cat <<EOF
You are ${AGENT_ID}. Read /root/.openclaw/workspace/swarm/SYSTEM.md for your instructions.

## 📋 Work Process — Follow IN ORDER:

**STEP 1: Research.** Use web_search for current best practices and examples.
**STEP 2: Plan.** Post your plan to the topic via send.sh before coding.
**STEP 3: Implement.** Write the code.
**STEP 4: Test.** Run tests, verify with curl/browser. Don't just say "done".
**STEP 5: Verify.** Provide concrete proof: test output, API responses, screenshots.

**Task:** ${TASK_DESC}

**Report to topic ${THREAD_ID}:**
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "message"
\`\`\`

${LESSONS}

**SELF-REVIEW before done:**
1. Take screenshot if UI change
2. Look at it — is the issue actually fixed?
3. If ANY bug visible → fix and retry
4. Only report done when it's PERFECT

**When DONE (ALL steps mandatory):**

1. Verify: \`bash /root/.openclaw/workspace/swarm/verify-before-done.sh\`
2. Report to topic:
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "✅ הושלם: <summary>"
\`\`\`
3. Report to General:
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh or 1 "✅ ${AGENT_ID}-${THREAD_ID} הושלם: <summary>"
\`\`\`
4. Done marker:
\`\`\`bash
bash /root/.openclaw/workspace/swarm/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "<summary>"
\`\`\`
5. Learning:
\`\`\`bash
bash /root/.openclaw/workspace/swarm/learn.sh score ${AGENT_ID} task-${THREAD_ID}-\$(date +%s) pass "Completed: ${TASK_DESC}"
\`\`\`

**If FAILED:**
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "❌ נכשל: <reason>"
bash /root/.openclaw/workspace/swarm/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "FAILED: <reason>"
\`\`\`
EOF
