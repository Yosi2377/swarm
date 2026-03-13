#!/bin/bash
# auto-loop.sh — Automatic retry loop for agent tasks
# Usage: auto-loop.sh <agent_id> <thread_id> <prompt_file> <check_command> [max_retries]
set -uo pipefail

[[ "${1:-}" == "--help" || $# -lt 4 ]] && { echo "Usage: auto-loop.sh <agent_id> <thread_id> <prompt_file> <check_command> [max_retries]"; exit 0; }

AGENT="$1"; THREAD="$2"; PROMPT_FILE="$3"; CHECK_CMD="$4"; MAX=${5:-3}
TASK_DIR="/tmp/engine-tasks"; STEP_DIR="/tmp/engine-steps"
mkdir -p "$TASK_DIR" "$STEP_DIR"

PREFIX="${AGENT}-${THREAD}"

for ATTEMPT in $(seq 1 "$MAX"); do
  echo "[auto-loop] Attempt $ATTEMPT/$MAX for $PREFIX"
  
  # Copy prompt to attempt file
  ATTEMPT_FILE="$TASK_DIR/${PREFIX}-attempt${ATTEMPT}.prompt"
  cp "$PROMPT_FILE" "$ATTEMPT_FILE"
  
  # Write task metadata
  echo "{\"agent\":\"$AGENT\",\"thread\":\"$THREAD\",\"attempt\":$ATTEMPT,\"prompt_file\":\"$ATTEMPT_FILE\",\"started\":\"$(date -Iseconds)\"}" \
    > "$TASK_DIR/${PREFIX}-meta.json"
  
  # Wait for done marker (poll every 10s, max 5min)
  DONE_FILE="$STEP_DIR/${PREFIX}.done"
  WAITED=0
  while [[ ! -f "$DONE_FILE" ]] && [[ $WAITED -lt 300 ]]; do
    sleep 10; WAITED=$((WAITED + 10))
  done
  
  if [[ ! -f "$DONE_FILE" ]]; then
    echo "[auto-loop] Timeout waiting for $DONE_FILE"
    ERROR="Timeout after 5 minutes"
  else
    rm -f "$DONE_FILE"
    # Run check
    CHECK_OUTPUT=$(eval "$CHECK_CMD" 2>&1) && { echo "[auto-loop] PASS on attempt $ATTEMPT"; exit 0; }
    ERROR="$CHECK_OUTPUT"
    echo "[auto-loop] FAIL: $ERROR"
  fi
  
  # If not last attempt, signal retry
  if [[ $ATTEMPT -lt $MAX ]]; then
    # Enrich prompt with error
    NEW_PROMPT="$TASK_DIR/${PREFIX}-attempt$((ATTEMPT+1)).prompt"
    cat "$ATTEMPT_FILE" > "$NEW_PROMPT"
    echo -e "\n\n--- RETRY (attempt $((ATTEMPT+1))/$MAX) ---\nPrevious attempt failed:\n$ERROR\n\nFix the issue and try again." >> "$NEW_PROMPT"
    PROMPT_FILE="$NEW_PROMPT"
    
    # Signal retry needed (orchestrator picks this up)
    echo "{\"attempt\":$((ATTEMPT+1)),\"error\":$(echo "$ERROR" | head -5 | jq -Rs .),\"prompt_file\":\"$NEW_PROMPT\"}" \
      > "$TASK_DIR/${PREFIX}-retry.json"
    echo "[auto-loop] Retry signal written, waiting for re-spawn..."
  fi
done

echo "[auto-loop] FAILED after $MAX attempts: $ERROR"
exit 1
