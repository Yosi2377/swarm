#!/bin/bash
# full-pipeline.sh — Complete task pipeline from dispatch to verify
# This is what the orchestrator calls for each task
# Usage: full-pipeline.sh <agent_id> <thread_id> <task_description> <url_to_verify> [project_dir]
#
# Flow:
# 1. Generate task prompt with contract (dispatch-task.sh)
# 2. Output prompt for sessions_spawn
# 3. After agent done → auto-verify-and-report.sh handles everything
#
# The orchestrator should:
# 1. TASK=$(bash full-pipeline.sh dispatch <agent_id> <thread_id> <desc> <url> [project_dir])
# 2. sessions_spawn with $TASK
# 3. When done detected: bash full-pipeline.sh verify <agent_id> <thread_id> <url> [summary]

ACTION="${1:?Usage: full-pipeline.sh <dispatch|verify> <agent_id> <thread_id> ...}"
shift

case "$ACTION" in
  dispatch)
    AGENT_ID="$1" THREAD_ID="$2" TASK_DESC="$3" URL="$4" PROJECT_DIR="$5"
    SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
    
    # Generate prompt with contract
    PROMPT=$(bash "${SWARM_DIR}/dispatch-task.sh" "$AGENT_ID" "$THREAD_ID" "$TASK_DESC" "$PROJECT_DIR")
    
    # Add the URL to verify after completion
    echo "$PROMPT"
    echo ""
    echo "## 📍 URL to Verify After Completion"
    echo "The orchestrator will verify: $URL"
    echo "Make sure this URL reflects your changes before reporting done."
    ;;
    
  verify)
    AGENT_ID="$1" THREAD_ID="$2" URL="$3" SUMMARY="$4"
    SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
    
    # Full auto-verification with screenshots and reporting
    bash "${SWARM_DIR}/auto-verify-and-report.sh" "$AGENT_ID" "$THREAD_ID" "$URL" "$SUMMARY"
    ;;
    
  *)
    echo "Unknown action: $ACTION. Use dispatch or verify."
    exit 1
    ;;
esac
