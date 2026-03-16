#!/bin/bash
# Auto-Retry Watcher — called by orchestrator heartbeat
# Checks /tmp/agent-done/ for completed agents AND /tmp/retry-request-*.json for retries
# Output: JSON summary

DONE_DIR="/tmp/agent-done"
SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="${SWARM_DIR}/core"
LOG_DIR="${SWARM_DIR}/logs"
MAX_RETRIES="${MAX_RETRIES:-3}"
RESULTS=()
PROCESSED=0
PASSED=0
RETRIED=0
ESCALATED=0
SKIPPED=0

mkdir -p "$DONE_DIR" /tmp/agent-tasks "$LOG_DIR"

# Exit cleanly if no done files
shopt -s nullglob
FILES=("$DONE_DIR"/*.json)
if [ ${#FILES[@]} -eq 0 ]; then
  echo '{"processed":0,"passed":0,"retried":0,"escalated":0,"skipped":0,"results":[]}'
  exit 0
fi

for f in "${FILES[@]}"; do
  BASENAME=$(basename "$f" .json)
  
  # Skip already verified
  VERIFIED=$(node -e "try{const d=JSON.parse(require('fs').readFileSync('$f','utf8'));console.log(d.verified?'yes':'no')}catch(e){console.log('no')}" 2>/dev/null)
  if [ "$VERIFIED" = "yes" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Extract agentId and threadId from filename (format: agentId-threadId)
  AGENT_ID=$(node -e "try{const d=JSON.parse(require('fs').readFileSync('$f','utf8'));console.log(d.agentId||d.agent_id||'$BASENAME'.split('-')[0])}catch(e){console.log('$BASENAME'.split('-')[0])}" 2>/dev/null)
  THREAD_ID=$(node -e "try{const d=JSON.parse(require('fs').readFileSync('$f','utf8'));console.log(d.threadId||d.thread_id||'$BASENAME'.split('-').slice(1).join('-'))}catch(e){console.log('unknown')}" 2>/dev/null)

  # Run auto-retry-runner
  RESULT=$(node -e "
    const { handleAgentCompletion } = require('$CORE_DIR/auto-retry-runner.js');
    handleAgentCompletion('$AGENT_ID', '$THREAD_ID')
      .then(r => console.log(JSON.stringify(r)))
      .catch(e => console.log(JSON.stringify({action:'error',error:e.message})));
  " 2>/dev/null)

  ACTION=$(echo "$RESULT" | node -e "try{const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(d.action)}catch(e){console.log('error')}" 2>/dev/null)

  case "$ACTION" in
    pass)
      PASSED=$((PASSED + 1))
      # Mark as verified in done file
      node -e "const f='$f';const d=JSON.parse(require('fs').readFileSync(f,'utf8'));d.verified=true;d.verified_at=new Date().toISOString();require('fs').writeFileSync(f,JSON.stringify(d,null,2))" 2>/dev/null
      ;;
    retry)
      RETRIED=$((RETRIED + 1))
      # retry-request file already created by auto-retry-runner
      ;;
    escalate)
      ESCALATED=$((ESCALATED + 1))
      # escalate file already created by auto-retry-runner
      ;;
    *)
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac

  PROCESSED=$((PROCESSED + 1))
  RESULTS+=("$RESULT")
done

# --- Phase 2: Process retry requests from watchdog ---
RETRY_PROCESSED=0
shopt -s nullglob
RETRY_FILES=(/tmp/retry-request-*.json)
for rf in "${RETRY_FILES[@]}"; do
  RETRY_DATA=$(cat "$rf" 2>/dev/null)
  [ -z "$RETRY_DATA" ] && continue

  R_AGENT=$(echo "$RETRY_DATA" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.agentId||'')}catch{console.log('')}" 2>/dev/null)
  R_THREAD=$(echo "$RETRY_DATA" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.threadId||'')}catch{console.log('')}" 2>/dev/null)
  R_COUNT=$(echo "$RETRY_DATA" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.retryCount||1)}catch{console.log(1)}" 2>/dev/null)
  R_REASON=$(echo "$RETRY_DATA" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.reason||'unknown')}catch{console.log('unknown')}" 2>/dev/null)
  R_TASK=$(echo "$RETRY_DATA" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.originalTask||'')}catch{console.log('')}" 2>/dev/null)
  R_PROGRESS=$(echo "$RETRY_DATA" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.progressSummary||'none')}catch{console.log('none')}" 2>/dev/null)

  [ -z "$R_AGENT" ] || [ -z "$R_THREAD" ] && continue

  # Check max retries
  if [ "$R_COUNT" -gt "$MAX_RETRIES" ]; then
    echo "[$(date -Iseconds)] ESCALATE: ${R_AGENT}-${R_THREAD} exceeded max retries ($MAX_RETRIES)" >> "$LOG_DIR/retries.log"
    # Update task to failed_terminal
    TASK_FILE="/tmp/agent-tasks/${R_AGENT}-${R_THREAD}.json"
    if [ -f "$TASK_FILE" ]; then
      node -e "const f='$TASK_FILE';const d=JSON.parse(require('fs').readFileSync(f,'utf8'));d.status='failed_terminal';d.failure_reason='max retries exceeded';require('fs').writeFileSync(f,JSON.stringify(d,null,2))" 2>/dev/null
    fi
    rm -f "$rf"
    ESCALATED=$((ESCALATED + 1))
    RESULTS+=("{\"action\":\"escalate\",\"taskId\":\"${R_AGENT}-${R_THREAD}\",\"reason\":\"max_retries\"}")
    continue
  fi

  # Build enriched retry prompt
  ENRICHED_CONTEXT="## RETRY ATTEMPT ${R_COUNT}/${MAX_RETRIES}
Previous attempt failed: ${R_REASON}

### What was already done:
${R_PROGRESS}

### Instructions for this retry:
- The previous attempt got stuck/failed. Avoid the same issue.
- Work more carefully and report progress frequently.
- If the same approach fails, try an alternative.

### Original task:
${R_TASK}"

  # Re-dispatch
  if [ -f "${SWARM_DIR}/dispatch-task.sh" ]; then
    # Update task metadata for retry
    TASK_FILE="/tmp/agent-tasks/${R_AGENT}-${R_THREAD}.json"
    if [ -f "$TASK_FILE" ]; then
      node -e "const f='$TASK_FILE';const d=JSON.parse(require('fs').readFileSync(f,'utf8'));d.status='running';d.retries=${R_COUNT};d.last_retry=new Date().toISOString();require('fs').writeFileSync(f,JSON.stringify(d,null,2))" 2>/dev/null
    fi

    # Remove old done marker if any
    rm -f "/tmp/agent-done/${R_AGENT}-${R_THREAD}.json"

    echo "[$(date -Iseconds)] RETRY: ${R_AGENT}-${R_THREAD} attempt ${R_COUNT} reason=${R_REASON}" >> "$LOG_DIR/retries.log"
    RETRIED=$((RETRIED + 1))
    RESULTS+=("{\"action\":\"retry\",\"taskId\":\"${R_AGENT}-${R_THREAD}\",\"attempt\":${R_COUNT}}")
  fi

  # Delete retry request file
  rm -f "$rf"
  RETRY_PROCESSED=$((RETRY_PROCESSED + 1))
done

# Output JSON summary
RESULTS_JSON=$(printf '%s\n' "${RESULTS[@]}" | node -e "
  const lines=require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n').filter(Boolean);
  const arr=lines.map(l=>{try{return JSON.parse(l)}catch(e){return {error:l}}});
  console.log(JSON.stringify(arr));
" 2>/dev/null || echo '[]')

echo "{\"processed\":$PROCESSED,\"passed\":$PASSED,\"retried\":$RETRIED,\"escalated\":$ESCALATED,\"skipped\":$SKIPPED,\"retryRequestsProcessed\":$RETRY_PROCESSED,\"results\":$RESULTS_JSON}"
