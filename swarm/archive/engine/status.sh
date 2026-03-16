#!/bin/bash
# status.sh — Quick status check for engine tasks
# Usage: status.sh
set -uo pipefail

STATUS_FILE="/tmp/engine-status.json"
TASK_DIR="/tmp/engine-tasks"
STEP_DIR="/tmp/engine-steps"
mkdir -p "$TASK_DIR" "$STEP_DIR"

echo "=== Swarm Engine Status ==="
echo "Time: $(date -Iseconds)"
echo ""

# From status file if available
if [[ -f "$STATUS_FILE" ]]; then
  UPDATED=$(jq -r '.updated // "unknown"' "$STATUS_FILE")
  echo "Last scan: $UPDATED"
  echo ""

  ACTIVE=$(jq '.active | length' "$STATUS_FILE" 2>/dev/null || echo 0)
  COMPLETED=$(jq '.completed | length' "$STATUS_FILE" 2>/dev/null || echo 0)
  RETRIES=$(jq '.retries | length' "$STATUS_FILE" 2>/dev/null || echo 0)
  STUCK=$(jq '.stuck | length' "$STATUS_FILE" 2>/dev/null || echo 0)

  echo "📊 Active: $ACTIVE | ✅ Completed: $COMPLETED | 🔄 Retries: $RETRIES | ⚠️ Stuck: $STUCK"
  echo ""

  [[ $ACTIVE -gt 0 ]] && { echo "--- Active Tasks ---"; jq -r '.active[] | "  \(.agent)-\(.thread) (\(.elapsed))"' "$STATUS_FILE" 2>/dev/null; echo ""; }
  [[ $RETRIES -gt 0 ]] && { echo "--- Pending Retries ---"; jq -c '.retries[]' "$STATUS_FILE" 2>/dev/null; echo ""; }
  [[ $STUCK -gt 0 ]] && { echo "--- Stuck Tasks ---"; jq -r '.stuck[] | "  ⚠️ \(.agent)-\(.thread) (\(.elapsed))"' "$STATUS_FILE" 2>/dev/null; echo ""; }
else
  echo "(No status file — monitor not running?)"
  echo ""
fi

# Direct scan of task files
echo "--- Task Files ---"
TASK_COUNT=$(ls "$TASK_DIR"/*.prompt 2>/dev/null | wc -l)
DONE_COUNT=$(ls "$STEP_DIR"/*.done 2>/dev/null | wc -l)
RETRY_COUNT=$(ls "$TASK_DIR"/*-retry.json 2>/dev/null | wc -l)
echo "Prompts: $TASK_COUNT | Done markers: $DONE_COUNT | Retry signals: $RETRY_COUNT"
