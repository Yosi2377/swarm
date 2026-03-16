#!/bin/bash
# hooks.sh — Pre/Post task hooks
# Inspired by Ruflo's hook system
# Usage: hooks.sh pre <agent> <task_id> <description> [project_dir]
#        hooks.sh post <agent> <task_id> <status> [project_dir]

set -uo pipefail

HOOK_TYPE="${1:?Usage: hooks.sh pre|post <agent> <task_id> <description|status> [project_dir]}"
AGENT="${2:?Missing agent}"
TASK_ID="${3:?Missing task_id}"
ARG4="${4:?Missing description/status}"
PROJECT_DIR="${5:-}"

SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_DIR="${SWARM_DIR}/engine"

case "$HOOK_TYPE" in
  pre)
    DESCRIPTION="$ARG4"
    ENHANCED_PROMPT=""

    # 1. Inject lessons from learning system
    LESSONS=""
    LESSONS=$(bash "${SWARM_DIR}/engine/learn.sh" inject "$AGENT" "$DESCRIPTION" 2>/dev/null | head -50) || true
    if [ -n "$LESSONS" ]; then
      ENHANCED_PROMPT="${ENHANCED_PROMPT}
## 🧠 Past Lessons
${LESSONS}
"
    fi

    # 2. Run pretrain if project_dir given
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
      KNOWLEDGE_FILE=$(bash "${ENGINE_DIR}/pretrain.sh" "$PROJECT_DIR" 2>/dev/null) || true
      if [ -n "$KNOWLEDGE_FILE" ] && [ -f "$KNOWLEDGE_FILE" ]; then
        KNOWLEDGE=$(cat "$KNOWLEDGE_FILE")
        ENHANCED_PROMPT="${ENHANCED_PROMPT}
## 📦 Project Knowledge
\`\`\`json
${KNOWLEDGE}
\`\`\`
"
      fi
    fi

    # 3. Record task start time
    bash "${SWARM_DIR}/engine/learn.sh" score "$AGENT" success "task-${TASK_ID}-start" 2>/dev/null || true

    # Output enhanced prompt additions
    echo "$ENHANCED_PROMPT"
    ;;

  post)
    STATUS="$ARG4"

    # 1. Record metrics
    bash "${SWARM_DIR}/engine/learn.sh" record "$AGENT" "$TASK_ID" "$STATUS" 2>/dev/null || true

    # 2. Stop timer
    bash "${SWARM_DIR}/engine/learn.sh" score "$AGENT" "$STATUS" "task-${TASK_ID}-end" 2>/dev/null || true

    # 3. Run verification if status is success
    if [ "$STATUS" = "success" ] || [ "$STATUS" = "done" ] || [ "$STATUS" = "completed" ]; then
      VERIFY_EXIT=0
      if [ -f "${SWARM_DIR}/verify-task.sh" ]; then
        bash "${SWARM_DIR}/verify-task.sh" "$AGENT" "$TASK_ID" "$PROJECT_DIR" 2>/dev/null || VERIFY_EXIT=$?
      fi

      if [ $VERIFY_EXIT -eq 1 ]; then
        echo "RETRY"
        # Trigger self-correct if available
        if [ -f "${ENGINE_DIR}/self-correct.sh" ]; then
          bash "${ENGINE_DIR}/self-correct.sh" "$AGENT" "$TASK_ID" 2>/dev/null || true
        fi
        exit 1
      elif [ $VERIFY_EXIT -eq 2 ]; then
        echo "ESCALATE"
        exit 2
      else
        echo "PASS"
      fi
    else
      # Record failure
      bash "${SWARM_DIR}/engine/learn.sh" save "$AGENT" "task-${TASK_ID}" "fail" "Task failed with status: ${STATUS}" 2>/dev/null || true
      echo "RECORDED_FAILURE"
    fi
    ;;

  *)
    echo "Unknown hook type: $HOOK_TYPE (use pre or post)" >&2
    exit 1
    ;;
esac
