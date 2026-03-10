#!/bin/bash
# Usage: bash done-marker.sh <label> <topic_id> "summary"
LABEL="$1"
TOPIC="$2"
SUMMARY="$3"
SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p /tmp/agent-done
echo "{\"label\":\"$LABEL\",\"topic\":\"$TOPIC\",\"summary\":\"$SUMMARY\",\"timestamp\":\"$(date -Iseconds)\",\"reported\":false}" > /tmp/agent-done/$LABEL.json

# Extract agent_id and thread_id from label (format: agent_id-thread_id)
AGENT_ID=$(echo "$LABEL" | rev | cut -d'-' -f2- | rev)
THREAD_ID=$(echo "$LABEL" | rev | cut -d'-' -f1 | rev)

# Update task status to verifying
TASK_FILE="/tmp/agent-tasks/${LABEL}.json"
if [ -f "$TASK_FILE" ]; then
  node -e "
    const fs = require('fs');
    const meta = JSON.parse(fs.readFileSync('$TASK_FILE', 'utf8'));
    const now = Date.now();
    meta.status = 'verifying';
    if (meta.task_state) {
      meta.task_state.history.push({ from: meta.task_state.status, to: 'verifying', reason: 'Agent reported done', timestamp: now });
      meta.task_state.status = 'verifying';
      meta.task_state.updatedAt = now;
    }
    meta.completed_at = new Date().toISOString();
    meta.summary = $(printf '%s' "$SUMMARY" | node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8')))");
    fs.writeFileSync('$TASK_FILE', JSON.stringify(meta, null, 2));
    console.log('Status updated to verifying');
  " 2>/dev/null
fi
