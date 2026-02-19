#!/bin/bash
# journal.sh — Structured event journal for pipeline runs
# Usage: journal.sh <task-id> <event-type> '<json-data>'
# Events: TASK_STARTED, ITERATION_START, TESTS_RUN, SCREENSHOT_TAKEN,
#         QUALITY_SCORED, ITERATION_END, TASK_COMPLETED, TASK_FAILED

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNS_DIR="$SCRIPT_DIR/runs"

if [ $# -lt 2 ]; then
  echo "Usage: journal.sh <task-id> <event-type> [json-data]"
  exit 1
fi

TASK_ID="$1"
EVENT_TYPE="$2"
EVENT_DATA="${3:-"{}"}"

TASK_DIR="$RUNS_DIR/$TASK_ID"
JOURNAL_DIR="$TASK_DIR/journal"
mkdir -p "$JOURNAL_DIR"

# Find next sequence number
LAST=$(ls "$JOURNAL_DIR"/*.json 2>/dev/null | sort -V | tail -1 | grep -oP '\d+' | tail -1)
NEXT=$(printf "%03d" $(( ${LAST:-0} + 1 )))

EVENT_FILE="$JOURNAL_DIR/${NEXT}.json"

cat > "$EVENT_FILE" <<EOF
{"seq":$((10#$NEXT)),"event":"$EVENT_TYPE","task":"$TASK_ID","ts":"$(date -Iseconds)","data":$EVENT_DATA}
EOF

echo "$EVENT_FILE"
