#!/bin/bash
# Progress Report — agents call this to report what they're doing
# Usage: progress-report.sh <agent_id> <thread_id> "message" [step_number]

AGENT_ID="${1:?Usage: progress-report.sh <agent_id> <thread_id> \"message\" [step]}"
THREAD_ID="${2:?Missing thread_id}"
MESSAGE="${3:?Missing message}"
STEP="${4:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

node -e "
  const { reportProgress } = require('${SWARM_DIR}/core/progress-tracker');
  const step = '${STEP}' ? parseInt('${STEP}', 10) : undefined;
  const result = reportProgress('${AGENT_ID}', '${THREAD_ID}', $(printf '%s' "$MESSAGE" | node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync(0,'utf8')))"), step);
  console.log(JSON.stringify({ ok: true, step: result.step, timestamp: result.timestamp }));
" 2>/dev/null || echo '{"ok":false,"error":"progress-tracker failed"}'
