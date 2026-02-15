#!/bin/bash
# checkpoint.sh — Durable Execution: checkpoint + resume for tasks
# Usage:
#   checkpoint.sh save <task_id> <step_name> [state_json]  — Save checkpoint
#   checkpoint.sh resume <task_id>                         — Get last checkpoint
#   checkpoint.sh list <task_id>                           — List all checkpoints
#   checkpoint.sh clean <task_id>                          — Remove checkpoints
set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKPOINT_DIR="$SWARM_DIR/learning/checkpoints"
mkdir -p "$CHECKPOINT_DIR"

case "${1:-help}" in

save)
  TASK_ID="${2:-}"
  STEP="${3:-}"
  STATE="${4:-{}}"
  
  if [ -z "$TASK_ID" ] || [ -z "$STEP" ]; then
    echo "Usage: checkpoint.sh save <task_id> <step_name> [state_json]"
    exit 1
  fi
  
  TASK_DIR="$CHECKPOINT_DIR/task-$TASK_ID"
  mkdir -p "$TASK_DIR"
  NOW=$(date -Iseconds)
  SEQ=$(find "$TASK_DIR" -name "*.json" 2>/dev/null | wc -l)
  
  python3 -c "
import json
data = {
    'taskId': $TASK_ID,
    'step': '$STEP',
    'sequence': $SEQ,
    'timestamp': '$NOW',
    'state': json.loads('$STATE') if '$STATE' != '{}' else {}
}
with open('$TASK_DIR/${SEQ}-${STEP}.json', 'w') as f:
    json.dump(data, f, indent=2)
"
  
  echo "💾 Checkpoint saved: step $SEQ ($STEP) for task #$TASK_ID"
  ;;

resume)
  TASK_ID="${2:-}"
  if [ -z "$TASK_ID" ]; then
    echo "Usage: checkpoint.sh resume <task_id>"
    exit 1
  fi
  
  TASK_DIR="$CHECKPOINT_DIR/task-$TASK_ID"
  if [ ! -d "$TASK_DIR" ]; then
    echo "NO_CHECKPOINT"
    exit 0
  fi
  
  # Get latest checkpoint
  LATEST=$(ls "$TASK_DIR"/*.json 2>/dev/null | sort -V | tail -1)
  if [ -z "$LATEST" ]; then
    echo "NO_CHECKPOINT"
    exit 0
  fi
  
  echo "📍 Last checkpoint for task #$TASK_ID:"
  cat "$LATEST"
  ;;

list)
  TASK_ID="${2:-}"
  if [ -z "$TASK_ID" ]; then
    echo "Usage: checkpoint.sh list <task_id>"
    exit 1
  fi
  
  TASK_DIR="$CHECKPOINT_DIR/task-$TASK_ID"
  if [ ! -d "$TASK_DIR" ]; then
    echo "No checkpoints for task #$TASK_ID"
    exit 0
  fi
  
  echo "📋 Checkpoints for task #$TASK_ID:"
  for f in "$TASK_DIR"/*.json; do
    [ -f "$f" ] || continue
    STEP=$(python3 -c "import json; print(json.load(open('$f'))['step'])" 2>/dev/null)
    TS=$(python3 -c "import json; print(json.load(open('$f'))['timestamp'])" 2>/dev/null)
    echo "  $(basename "$f" .json): $STEP ($TS)"
  done
  ;;

clean)
  TASK_ID="${2:-}"
  if [ -z "$TASK_ID" ]; then
    echo "Usage: checkpoint.sh clean <task_id>"
    exit 1
  fi
  
  rm -rf "$CHECKPOINT_DIR/task-$TASK_ID"
  echo "🗑️ Checkpoints cleaned for task #$TASK_ID"
  ;;

*)
  echo "💾 Checkpoint System (Durable Execution)"
  echo "Usage:"
  echo "  checkpoint.sh save <task_id> <step> [state_json]  — Save checkpoint"
  echo "  checkpoint.sh resume <task_id>                    — Get last checkpoint"
  echo "  checkpoint.sh list <task_id>                      — List checkpoints"
  echo "  checkpoint.sh clean <task_id>                     — Remove checkpoints"
  ;;
esac
