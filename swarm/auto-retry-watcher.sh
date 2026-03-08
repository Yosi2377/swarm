#!/bin/bash
# Auto-Retry Watcher — called by orchestrator heartbeat
# Checks /tmp/agent-done/ for completed agents and processes them
# Output: JSON summary

DONE_DIR="/tmp/agent-done"
CORE_DIR="$(dirname "$0")/core"
RESULTS=()
PROCESSED=0
PASSED=0
RETRIED=0
ESCALATED=0
SKIPPED=0

mkdir -p "$DONE_DIR" /tmp/agent-tasks

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

# Output JSON summary
RESULTS_JSON=$(printf '%s\n' "${RESULTS[@]}" | node -e "
  const lines=require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n').filter(Boolean);
  const arr=lines.map(l=>{try{return JSON.parse(l)}catch(e){return {error:l}}});
  console.log(JSON.stringify(arr));
" 2>/dev/null || echo '[]')

echo "{\"processed\":$PROCESSED,\"passed\":$PASSED,\"retried\":$RETRIED,\"escalated\":$ESCALATED,\"skipped\":$SKIPPED,\"results\":$RESULTS_JSON}"
