#!/bin/bash
# dispatch-task.sh — Full orchestrator dispatch with reliability layer
# Usage: dispatch-task.sh <agent_id> <thread_id> <task_description> [project_dir]
# Output: Combined prompt (spawn-agent + contract) ready for sessions_spawn

AGENT_ID="${1:?Usage: dispatch-task.sh <agent_id> <thread_id> <task_description> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-resolve project config if project_dir given
if [ -n "$PROJECT_DIR" ]; then
  PROJECT_CONFIG=$(node -e "
    const { getProject } = require('${SWARM_DIR}/core/project-ports');
    const p = getProject('${PROJECT_DIR}');
    console.log(JSON.stringify(p));
  " 2>/dev/null)
fi

# Step 1: Generate base agent prompt (existing spawn-agent.sh)
BASE_PROMPT=$(bash "${SWARM_DIR}/spawn-agent.sh" "$AGENT_ID" "$THREAD_ID" "$TASK_DESC" "" "$PROJECT_DIR" 2>/dev/null)

# Step 2: Generate contract + state (new reliability layer) with full project config
CONTRACT_PROMPT=$(node -e "
  const bridge = require('${SWARM_DIR}/core/orchestrator-bridge');
  const { getProject } = require('${SWARM_DIR}/core/project-ports');
  const projectConfig = '${PROJECT_DIR}' ? getProject('${PROJECT_DIR}') : {};
  const result = bridge.prepareTask(process.argv[1], process.argv[2], process.argv[3], projectConfig);
  if (result.errors) { console.error(JSON.stringify(result.errors)); process.exit(1); }
  console.log(result.agentPrompt);
" "$TASK_DESC" "$AGENT_ID" "$THREAD_ID" 2>/dev/null)

# Step 3: Update state to "running"
node -e "
  const { advanceTask, TASKS_DIR } = require('${SWARM_DIR}/core/task-runner');
  const fs = require('fs');
  const path = require('path');
  // Find contract ID from task metadata
  const metaPath = path.join(TASKS_DIR, '${AGENT_ID}-${THREAD_ID}.json');
  if (fs.existsSync(metaPath)) {
    const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
    meta.status = 'running';
    meta.started_at = new Date().toISOString();
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
  }
" 2>/dev/null

# Step 4: Combine
cat <<PROMPT
${BASE_PROMPT}

## 🎯 Task Contract (Auto-Generated)
The following contract defines EXACTLY what will be verified when you report done.
An independent verifier will check EVERY criterion. Do not report done unless ALL pass.

${CONTRACT_PROMPT}

## MANDATORY: Progress Reports
Every 60 seconds of work, report progress:
\`\`\`bash
${SWARM_DIR}/progress-report.sh ${AGENT_ID} ${THREAD_ID} "what you're doing now"
\`\`\`
This is NOT optional. The watchdog will kill your task if no progress is reported for 3+ minutes.

## MANDATORY: Error Recovery
If you hit an error, DON'T just report done. Instead:
1. Try to fix it yourself (up to 3 attempts)
2. If still failing, explain what went wrong in detail
3. Create the done marker with status: "failed" not "completed"

## MANDATORY: Complex Task Handling
For complex tasks with multiple steps:
1. List all steps FIRST before starting
2. Complete each step and verify before moving to next
3. Report progress after each step
4. If one step fails, don't skip it — report the failure

## ⛔ MANDATORY BEFORE REPORTING DONE — SCREENSHOT PROTOCOL:
1. **NAVIGATE FIRST**: \`browser action=navigate url="THE_CORRECT_URL"\` — NOT whatever is already open!
2. **VERIFY you're on the right page**: \`browser action=snapshot\` — read the content, confirm it's the right URL
3. **ONLY THEN screenshot**: \`browser action=screenshot\`
4. **Send to topic + General via send.sh**

⚠️ **THE #1 AGENT MISTAKE**: Taking a screenshot of whatever page is already open from a PREVIOUS task.
If your screenshot shows BotVerse but your task was about the Dashboard — that's a FAIL.
**ALWAYS navigate to the correct URL before screenshotting. Every. Single. Time.**

## 📌 WHEN DONE — Create completion marker:
\`\`\`bash
mkdir -p /tmp/agent-done
echo '{"agent":"${AGENT_ID}","thread":"${THREAD_ID}","completed_at":"'\$(date -Iseconds)'"}' > /tmp/agent-done/${AGENT_ID}-${THREAD_ID}.json
\`\`\`
This marker triggers automatic verification. DO NOT skip this step.

## 🤝 Need Help? Consult Another Agent
If you're stuck on something outside your expertise:
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} 479 "[EMOJI] → [TARGET_EMOJI] | TYPE: consultation
QUESTION"
\`\`\`
Auto-routing: security→שומר, design→צייר, research→חוקר, testing→בודק

PROMPT
