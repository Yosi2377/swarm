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

# Step 0: Record task start in learning system
bash "${SWARM_DIR}/learn.sh" score "$AGENT_ID" success "task-${THREAD_ID}-start" 2>/dev/null || true
echo "📝 Task ${AGENT_ID}-${THREAD_ID} started at $(date -Iseconds)" >> "${SWARM_DIR}/learning/task_log.json" 2>/dev/null || true

# Step 0.5: Auto-detect task type and load template
TASK_LOWER=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]')
TEMPLATE_TYPE=""
if echo "$TASK_LOWER" | grep -qE '(fix|bug|broken|crash|error|repair|תקן|באג|שבור)'; then
  TEMPLATE_TYPE="code-fix"
elif echo "$TASK_LOWER" | grep -qE '(ui|css|design|style|layout|color|button|עיצוב|כפתור|צבע)'; then
  TEMPLATE_TYPE="ui-change"
elif echo "$TASK_LOWER" | grep -qE '(api|endpoint|route|rest|graphql)'; then
  TEMPLATE_TYPE="api-endpoint"
elif echo "$TASK_LOWER" | grep -qE '(config|env|environment|setting|הגדר)'; then
  TEMPLATE_TYPE="config-change"
elif echo "$TASK_LOWER" | grep -qE '(research|audit|investigate|check|scan|חקר|סריק|בדוק)'; then
  TEMPLATE_TYPE="investigation"
elif echo "$TASK_LOWER" | grep -qE '(add|feature|new|create|implement|הוסף|פיצ׳ר|חדש)'; then
  TEMPLATE_TYPE="add-feature"
fi

TEMPLATE_CONTENT=""
if [ -n "$TEMPLATE_TYPE" ]; then
  TEMPLATE_FILE="${SWARM_DIR}/templates/${TEMPLATE_TYPE}.md"
  if [ -f "$TEMPLATE_FILE" ]; then
    TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")
  fi
fi

# Step 0.6: Load top 5 lessons
LESSONS=""
LESSONS=$(bash "${SWARM_DIR}/learn.sh" inject "$AGENT_ID" "$TASK_DESC" 2>/dev/null | head -50) || true

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
    if (meta.task_state) {
      const now = Date.now();
      meta.task_state.history.push({ from: meta.task_state.status, to: 'running', reason: 'Agent dispatched', timestamp: now });
      meta.task_state.status = 'running';
      meta.task_state.updatedAt = now;
    }
    meta.status = 'running';
    meta.started_at = new Date().toISOString();
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
  }
" 2>/dev/null

# Step 4: Combine
cat <<PROMPT
${BASE_PROMPT}

## 📋 Structured Checkpoint Format (MANDATORY)
You MUST report progress using this EXACT format after each step:
\`\`\`
STEP 1: [description] → DONE/FAIL
STEP 2: [description] → DONE/FAIL
...
FINAL: [summary] → ALL_PASS/PARTIAL/FAIL
\`\`\`
If a step FAILs, explain WHY in one line before moving to the next step.
Do NOT skip this format. The orchestrator parses it automatically.

$(if [ -n "$TEMPLATE_CONTENT" ]; then
cat <<TMPL
## 🗺️ Task Template: ${TEMPLATE_TYPE}
Follow these steps IN ORDER. Do not skip steps. Check each checkpoint before moving on.

${TEMPLATE_CONTENT}
TMPL
fi)

$(if [ -n "$LESSONS" ]; then
cat <<LSNS
## 🧠 Lessons from Past Tasks (READ BEFORE STARTING)
${LESSONS}
LSNS
fi)

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

## 📌 WHEN DONE — Run self-verification BEFORE reporting:
\`\`\`bash
# Self-check before claiming done (agent-side)
if [ -n "${PROJECT_DIR}" ]; then
  cd "${PROJECT_DIR}" && npm test 2>/dev/null || echo "⚠️ Tests failed — fix before reporting done"
fi
\`\`\`

## 📌 THEN — Create completion marker:
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
