#!/bin/bash
# spawn-agent.sh — Standard agent task template
# Generates the task text with all mandatory footers (topic, send.sh, learn.sh, marker)
# Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>
#
# Output: prints the full task text to stdout (pipe to sessions_spawn)

AGENT_ID="${1:?Usage: spawn-agent.sh <agent_id> <thread_id> <task_description>}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

# Inject relevant lessons
LESSONS=$(bash "${SWARM_DIR}/inject-lessons.sh" "$TASK_DESC" 2>/dev/null || echo "")

cat <<EOF
You are ${AGENT_ID}. Read /root/.openclaw/workspace/swarm/SYSTEM.md for your instructions.

**Task:** ${TASK_DESC}

**Report to topic ${THREAD_ID}** — use send.sh for progress updates:
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "message"
\`\`\`

${LESSONS}

**BEFORE reporting done — MANDATORY SELF-REVIEW LOOP:**
If the task involves a web page or UI, you MUST repeat this loop until PERFECT:

1. Take a screenshot:
\`\`\`bash
/root/.openclaw/workspace/swarm/browser-test.sh screenshot "http://localhost:PORT" "/tmp/proof-${THREAD_ID}.png"
\`\`\`

2. **LOOK AT THE SCREENSHOT** using the image tool. Ask yourself:
   - Is the layout correct? No broken elements?
   - Are there "undefined", "NaN", empty sections, or missing data?
   - Do all links, buttons, and cards look professional?
   - Would I be embarrassed to show this to someone?

3. **If ANY issue found → FIX IT and go back to step 1.**
   Do NOT report done until zero issues remain.
   Send progress updates: \`/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "🔄 Found issue: X — fixing..."\`

4. Only when it's PERFECT — send the screenshot as proof:
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "📸 Screenshot — verified clean:" --photo /tmp/proof-${THREAD_ID}.png
\`\`\`

⚠️ **DO NOT say "done" with bugs visible in the screenshot! Fix everything first. No exceptions.**

**When DONE (MANDATORY — do ALL of these):**

1. Send completion message:
\`\`\`bash
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "✅ משימה הושלמה: ${TASK_DESC}"
\`\`\`

2. Log success to learning system:
\`\`\`bash
bash /root/.openclaw/workspace/swarm/learn.sh score ${AGENT_ID} task-${THREAD_ID}-\$(date +%s) pass "Completed: ${TASK_DESC}"
\`\`\`

3. Create done marker:
\`\`\`bash
mkdir -p /tmp/agent-done && python3 -c "import json; json.dump({'thread':${THREAD_ID},'status':'success','message':'${TASK_DESC}','agent':'${AGENT_ID}'}, open('/tmp/agent-done/${AGENT_ID}-${THREAD_ID}.json','w'))"
\`\`\`

**If FAILED:**
\`\`\`bash
bash /root/.openclaw/workspace/swarm/learn.sh score ${AGENT_ID} task-${THREAD_ID}-\$(date +%s) fail "Failed: <reason>"
bash /root/.openclaw/workspace/swarm/learn.sh lesson ${AGENT_ID} important 0.8 "Failed: ${TASK_DESC}" "<what went wrong and how to avoid>"
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "❌ משימה נכשלה: <reason>"
mkdir -p /tmp/agent-done && python3 -c "import json; json.dump({'thread':${THREAD_ID},'status':'failed','message':'נכשל: ${TASK_DESC}','agent':'${AGENT_ID}'}, open('/tmp/agent-done/${AGENT_ID}-${THREAD_ID}.json','w'))"
\`\`\`
EOF
