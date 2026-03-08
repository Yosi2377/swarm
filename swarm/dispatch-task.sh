#!/bin/bash
# dispatch-task.sh — Full orchestrator dispatch with reliability layer
# Usage: dispatch-task.sh <agent_id> <thread_id> <task_description> [project_dir]
# Output: Combined prompt (spawn-agent + contract) ready for sessions_spawn

AGENT_ID="${1:?Usage: dispatch-task.sh <agent_id> <thread_id> <task_description> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
TASK_DESC="${3:?Missing task_description}"
PROJECT_DIR="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

# Step 1: Generate base agent prompt (existing spawn-agent.sh)
BASE_PROMPT=$(bash "${SWARM_DIR}/spawn-agent.sh" "$AGENT_ID" "$THREAD_ID" "$TASK_DESC" "" "$PROJECT_DIR" 2>/dev/null)

# Step 2: Generate contract + state (new reliability layer)
CONTRACT_PROMPT=$(bash "${SWARM_DIR}/orchestrator-dispatch.sh" "$AGENT_ID" "$THREAD_ID" "$TASK_DESC" "$PROJECT_DIR" 2>/dev/null)

# Step 3: Combine
cat <<PROMPT
${BASE_PROMPT}

## 🎯 Task Contract (Auto-Generated)
The following contract defines EXACTLY what will be verified when you report done.
An independent verifier will check EVERY criterion. Do not report done unless ALL pass.

${CONTRACT_PROMPT}

## ⛔ MANDATORY BEFORE REPORTING DONE:
1. Take screenshot: \`browser action=screenshot\` or \`bash swarm/report-done.sh THREAD "summary"\`
2. Send screenshot to YOUR topic AND to General (topic 1) via send.sh with photo
3. If you skip screenshots, verification will FAIL automatically — screenshot_sent is an acceptance criterion
4. The orchestrator will NOT accept "done" without visual proof

## 🤝 Need Help? Consult Another Agent
If you're stuck on something outside your expertise:
\`\`\`bash
${SWARM_DIR}/send.sh ${AGENT_ID} 479 "[EMOJI] → [TARGET_EMOJI] | TYPE: consultation
QUESTION"
\`\`\`
Auto-routing: security→שומר, design→צייר, research→חוקר, testing→בודק

PROMPT
