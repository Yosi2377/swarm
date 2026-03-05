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

## 📋 Mandatory Work Process — Follow These Steps IN ORDER:

**STEP 1: Research first.** Use web_search to find current best practices, latest versions, and examples before writing any code. At least 2-3 searches relevant to the task.

**STEP 2: Plan.** Write a brief plan of what you'll change and why. Post it to the topic via send.sh before coding.

**STEP 3: Implement.** Write the code, following what you learned in research.

**STEP 4: Test.** Run tests and verify manually. Use curl, browser snapshots, or E2E tests as appropriate.

**STEP 5: Verify with counts/screenshots — don't just say 'done'.** Provide concrete evidence: DB counts, API responses, screenshots.

⚠️ **Do NOT skip Step 1 (Research).** Even if you think you know the answer, search first. Things change.

**Task:** ${TASK_DESC}

## 🛡️ MANDATORY Safety Rules (DB Operations)
- **BEFORE any delete/cleanup/drop operation on MongoDB:** run \`bash $PROJECT_DIR/scripts/pre-agent-backup.sh\`
- **AFTER any DB modification:** run integrity check:
  \`\`\`bash
  node -e "const m=require('mongoose');const{verifyIntegrity}=require('$PROJECT_DIR/lib/agent-safety');m.connect('mongodb://localhost/botverse').then(async()=>{const r=await verifyIntegrity(m.connection.db);console.log(r);process.exit(0)})"
  \`\`\`
- **If integrity check shows warnings (empty collections) → STOP and restore from backup**
- **NEVER use deleteMany with empty filter on agents, skills, posts, owners**
- **For cleanup tasks:** use \`safeDeleteMany\` from \`$PROJECT_DIR/lib/agent-safety.js\` instead of raw \`deleteMany\`
- **Violation of these rules = immediate task failure**

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

3. Create done marker (MANDATORY — this is how the orchestrator knows you finished):
\`\`\`bash
bash /root/.openclaw/workspace/swarm/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "summary of what you did"
\`\`\`

**If FAILED:**
\`\`\`bash
bash /root/.openclaw/workspace/swarm/learn.sh score ${AGENT_ID} task-${THREAD_ID}-\$(date +%s) fail "Failed: <reason>"
bash /root/.openclaw/workspace/swarm/learn.sh lesson ${AGENT_ID} important 0.8 "Failed: ${TASK_DESC}" "<what went wrong and how to avoid>"
/root/.openclaw/workspace/swarm/send.sh ${AGENT_ID} ${THREAD_ID} "❌ משימה נכשלה: <reason>"
bash /root/.openclaw/workspace/swarm/done-marker.sh "${AGENT_ID}-${THREAD_ID}" "${THREAD_ID}" "FAILED: <reason>"
\`\`\`
EOF
