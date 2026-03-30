#!/bin/bash
# dispatch-task.sh — Full orchestrator dispatch with reliability layer
# Usage: dispatch-task.sh <agent_id> <thread_id> <task_description> [project_dir]
# Output: Combined prompt (spawn-agent + contract) ready for sessions_spawn

# Rate guard — prevent API overload
bash "$(dirname "$0")/rate-guard.sh" 2>/dev/null

AGENT_ID_INPUT="${1:?Usage: dispatch-task.sh <agent_id|auto> <thread_id> <task_description> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

if echo "$THREAD_ID" | grep -q '^job-'; then
  node "${SWARM_DIR}/core/job-store.js" ensure-channel "$THREAD_ID" "$TASK_DESC" >/dev/null 2>&1 || true
fi

# Step -1: Smart routing — auto-select agent if "auto" or empty
if [ "$AGENT_ID_INPUT" = "auto" ] || [ -z "$AGENT_ID_INPUT" ]; then
  AGENT_ID=$(bash "${SWARM_DIR}/engine/route.sh" "$TASK_DESC" 2>/dev/null) || AGENT_ID="worker"
  echo "🧭 Auto-routed to: $AGENT_ID" >&2
else
  AGENT_ID="$AGENT_ID_INPUT"
fi

# Step -0.5: Pretrain — generate project knowledge if project_dir given
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
  KNOWLEDGE_FILE=$(bash "${SWARM_DIR}/engine/pretrain.sh" "$PROJECT_DIR" 2>/dev/null) || true
fi

# Step -0.25: Pre-task hooks
PRE_HOOK_OUTPUT=""
PRE_HOOK_OUTPUT=$(bash "${SWARM_DIR}/engine/hooks.sh" pre "$AGENT_ID" "$THREAD_ID" "$TASK_DESC" "$PROJECT_DIR" 2>/dev/null) || true

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

# Step 0.6: Detect if this is a multi-agent collaboration task
COLLAB_AGENTS=""
COLLAB_MODE=""
if echo "$TASK_LOWER" | grep -qE '(review|ביקורת|בדיקת קוד|code review)'; then
  COLLAB_MODE="review"
  # Auto-detect: reviewer = shomer for security, tester for tests, refactor for code quality
  case "$AGENT_ID" in
    koder) COLLAB_AGENTS="koder,shomer" ;;
    front) COLLAB_AGENTS="front,koder" ;;
    back) COLLAB_AGENTS="back,shomer" ;;
    *) COLLAB_AGENTS="${AGENT_ID},shomer" ;;
  esac
elif echo "$TASK_LOWER" | grep -qE '(architect|תכנון|design.*system|עיצוב.*מערכת|plan|debate|דיון|ויכוח)'; then
  COLLAB_MODE="collab"
  COLLAB_AGENTS="${AGENT_ID},shomer,front"
elif echo "$TASK_LOWER" | grep -qE '(compare|השווה|pros.*cons|יתרונות.*חסרונות|evaluate|הערכה)'; then
  COLLAB_MODE="debate"
  COLLAB_AGENTS="${AGENT_ID},researcher"
fi

# If collab detected, inject collab prompt AND auto-run collab session
COLLAB_PROMPT=""
COLLAB_AUTO_RUN="false"
if [ -n "$COLLAB_MODE" ]; then
  COLLAB_AUTO_RUN="true"
  COLLAB_PROMPT=$(node -e "
    const PI = require('${SWARM_DIR}/collab/prompt-injector');
    const pi = new PI();
    const agents = '${COLLAB_AGENTS}'.split(',');
    const prompt = pi.generate('${COLLAB_MODE}', {
      agentId: '${AGENT_ID}',
      participants: agents.filter(a => a !== '${AGENT_ID}'),
      topic: process.argv[1],
      conversationId: 'task-${THREAD_ID}',
    });
    console.log(prompt);
  " "$TASK_DESC" 2>/dev/null) || true
  
  if [ -n "$COLLAB_PROMPT" ]; then
    echo "🤝 Collab mode: ${COLLAB_MODE} (agents: ${COLLAB_AGENTS})" >&2
  fi
fi

# Step 0.6b: Load top 5 lessons
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

$(if [ -n "$PRE_HOOK_OUTPUT" ]; then
echo "$PRE_HOOK_OUTPUT"
fi)

$(if [ -n "$COLLAB_PROMPT" ]; then
cat <<COLLAB
## 🤝 Collaboration Protocol (${COLLAB_MODE} mode)
You are collaborating with: ${COLLAB_AGENTS}
The collaboration system is at: ${SWARM_DIR}/collab/

### Rules:
${COLLAB_PROMPT}

### How to collaborate:
1. After completing your part, post your work to the topic for review
2. If another agent posts feedback, READ it and RESPOND
3. Don't just agree — if you disagree, explain why
4. Use send.sh to communicate: ${SWARM_DIR}/send.sh <agent_id> ${THREAD_ID} "message"

### Collab session runner (for orchestrator use):
node ${SWARM_DIR}/collab/collab-session.js --task "YOUR_TASK" --agents "${COLLAB_AGENTS}" --topic ${THREAD_ID} --mode ${COLLAB_MODE}
COLLAB
fi)

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
**You MUST take a screenshot before reporting done. No exceptions. No screenshot = task FAILED.**

Use this command (works in sub-agents, no browser tool needed):
\`\`\`bash
bash /root/.openclaw/workspace/swarm/agent-screenshot.sh "http://localhost:4000/THE_PAGE" TOPIC_ID AGENT_ID "📸 תיאור קצר"
\`\`\`

Example:
\`\`\`bash
bash /root/.openclaw/workspace/swarm/agent-screenshot.sh "http://localhost:4000/" 11279 front "📸 Homepage after mobile UX fix"
\`\`\`

This takes a screenshot with puppeteer AND sends it to the topic automatically.
⚠️ **NO SCREENSHOT = AUTOMATIC FAIL. The orchestrator will reject your done marker.**

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

## 🪝 Post-Task Hooks (Auto-triggered)
When your task is complete, the orchestrator will run post-task hooks automatically:
- Record metrics to learning system
- Independent verification of deliverables
- Self-correction if verification fails
No action needed from you — just create the done marker as instructed above.

PROMPT

# Step 5: Auto-run collab session in background if detected
if [ "$COLLAB_AUTO_RUN" = "true" ] && [ -n "$COLLAB_MODE" ] && [ -n "$COLLAB_AGENTS" ]; then
  echo "🤝 AUTO-LAUNCHING collab session: mode=${COLLAB_MODE} agents=${COLLAB_AGENTS}" >&2
  
  # Save collab metadata for the task
  mkdir -p /tmp/agent-tasks
  META_FILE="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"
  if [ -f "$META_FILE" ]; then
    python3 -c "
import json
m = json.load(open('$META_FILE'))
m['collab_mode'] = '$COLLAB_MODE'
m['collab_agents'] = '$COLLAB_AGENTS'
m['collab_auto_run'] = True
json.dump(m, open('$META_FILE', 'w'), indent=2)
" 2>/dev/null
  fi
  
  # Launch collab session in background — agents discuss in the topic via Telegram
  nohup node "${SWARM_DIR}/collab/collab-session.js" \
    --task "$TASK_DESC" \
    --agents "$COLLAB_AGENTS" \
    --topic "$THREAD_ID" \
    --mode "$COLLAB_MODE" \
    >> "${SWARM_DIR}/logs/collab-${THREAD_ID}.log" 2>&1 &
  
  echo "🤝 Collab PID: $!" >&2
fi
