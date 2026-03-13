#!/bin/bash
# monitor.sh — Background monitor daemon for engine tasks
# Usage: monitor.sh [interval_seconds]
# Runs in background, checks task status periodically
set -uo pipefail

[[ "${1:-}" == "--help" ]] && { echo "Usage: monitor.sh [interval_seconds]"; exit 0; }

INTERVAL="${1:-30}"
TASK_DIR="/tmp/engine-tasks"; STEP_DIR="/tmp/engine-steps"
STATUS_FILE="/tmp/engine-status.json"
LOG_FILE="/tmp/engine-monitor.log"
mkdir -p "$TASK_DIR" "$STEP_DIR"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"; }

update_status() {
  local active=() completed=() retries=() stuck=()
  NOW=$(date +%s)

  # Check meta files for active tasks
  for meta in "$TASK_DIR"/*-meta.json; do
    [[ -f "$meta" ]] || continue
    AGENT=$(jq -r '.agent' "$meta" 2>/dev/null || continue)
    THREAD=$(jq -r '.thread' "$meta" 2>/dev/null)
    STARTED=$(jq -r '.started' "$meta" 2>/dev/null)
    PREFIX="${AGENT}-${THREAD}"
    START_TS=$(date -d "$STARTED" +%s 2>/dev/null || echo "$NOW")
    ELAPSED=$(( NOW - START_TS ))

    if [[ -f "$STEP_DIR/${PREFIX}.done" ]]; then
      completed+=("$(jq -n --arg a "$AGENT" --arg t "$THREAD" --arg e "${ELAPSED}s" '{agent:$a,thread:$t,elapsed:$e}')")
    elif [[ -f "$TASK_DIR/${PREFIX}-retry.json" ]]; then
      retries+=("$(cat "$TASK_DIR/${PREFIX}-retry.json")")
    elif [[ $ELAPSED -gt 600 ]]; then
      stuck+=("$(jq -n --arg a "$AGENT" --arg t "$THREAD" --arg e "${ELAPSED}s" '{agent:$a,thread:$t,elapsed:$e}')")
      log "STUCK: $PREFIX (${ELAPSED}s)"
    else
      active+=("$(jq -n --arg a "$AGENT" --arg t "$THREAD" --arg e "${ELAPSED}s" '{agent:$a,thread:$t,elapsed:$e}')")
    fi
  done

  # Write status
  jq -n \
    --argjson active "$(printf '%s\n' "${active[@]:-}" | jq -s '.')" \
    --argjson completed "$(printf '%s\n' "${completed[@]:-}" | jq -s '.')" \
    --argjson retries "$(printf '%s\n' "${retries[@]:-}" | jq -s '.')" \
    --argjson stuck "$(printf '%s\n' "${stuck[@]:-}" | jq -s '.')" \
    --arg updated "$(date -Iseconds)" \
    '{active:$active,completed:$completed,retries:$retries,stuck:$stuck,updated:$updated}' \
    > "$STATUS_FILE" 2>/dev/null
}

log "Monitor started (interval: ${INTERVAL}s)"

while true; do
  update_status
  sleep "$INTERVAL"
done
