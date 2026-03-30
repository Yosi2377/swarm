#!/bin/bash
# job-close.sh — close a job and send final summary back to #ops
# Usage: job-close.sh <agent_id> <job_id> <summary>

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="${1:?Usage: $0 <agent_id> <job_id> <summary>}"
JOB_ID="${2:?Usage: $0 <agent_id> <job_id> <summary>}"
SUMMARY="${3:?Usage: $0 <agent_id> <job_id> <summary>}"

node "$DIR/core/job-store.js" close "$JOB_ID" "$SUMMARY" >/dev/null
"$DIR/send.sh" "$AGENT_ID" "$JOB_ID" "$SUMMARY"
