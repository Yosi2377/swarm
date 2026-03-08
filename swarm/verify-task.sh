#!/bin/bash
# verify-task.sh — Full verification when agent reports done
# Usage: verify-task.sh <agent_id> <thread_id>
# Returns: exit 0 = pass, exit 1 = retry needed, exit 2 = escalate

AGENT_ID="${1:?Usage: verify-task.sh <agent_id> <thread_id>}"
THREAD_ID="${2:?Missing thread_id}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

# Run verification
RESULT=$(bash "${SWARM_DIR}/orchestrator-verify.sh" "$AGENT_ID" "$THREAD_ID" 2>/dev/null)
ACTION=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.action)" 2>/dev/null)

echo "$RESULT"

case "$ACTION" in
  pass)
    echo "✅ VERIFIED PASS"
    exit 0
    ;;
  retry)
    PROMPT=$(echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.prompt||'')" 2>/dev/null)
    echo "🔄 RETRY NEEDED"
    echo "RETRY_PROMPT: $PROMPT"
    exit 1
    ;;
  escalate)
    echo "🚨 ESCALATE TO HUMAN"
    exit 2
    ;;
  *)
    echo "⚠️ Unknown action: $ACTION"
    exit 1
    ;;
esac
