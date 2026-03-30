#!/bin/bash
# job-open.sh — open a new internal job and classify its IRC channel
# Usage: job-open.sh <agent_id> <title> [task_description]

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="${1:?Usage: $0 <agent_id> <title> [task_description]}"
TITLE="${2:?Usage: $0 <agent_id> <title> [task_description]}"
TASK_DESC="${3:-$TITLE}"

JOB_ID=$(node "$DIR/core/job-store.js" create "$TITLE" "$AGENT_ID")
CHANNEL=$(node "$DIR/core/job-store.js" ensure-channel "$JOB_ID" "$TASK_DESC")

echo "$JOB_ID $CHANNEL"
