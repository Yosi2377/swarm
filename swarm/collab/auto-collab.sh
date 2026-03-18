#!/bin/bash
# auto-collab.sh — Automatically run collaboration session after primary agent completes
# Called by verify-task.sh or heartbeat when collab metadata exists
# Usage: auto-collab.sh <agent_id> <thread_id>

AGENT_ID="${1:?Missing agent_id}"
THREAD_ID="${2:?Missing thread_id}"
SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check if task has collab metadata
META="/tmp/agent-tasks/${AGENT_ID}-${THREAD_ID}.json"
if [ ! -f "$META" ]; then
  echo "No task metadata found"
  exit 0
fi

COLLAB_MODE=$(python3 -c "import json; m=json.load(open('$META')); print(m.get('collab_mode',''))" 2>/dev/null)
COLLAB_AGENTS=$(python3 -c "import json; m=json.load(open('$META')); print(m.get('collab_agents',''))" 2>/dev/null)

if [ -z "$COLLAB_MODE" ] || [ -z "$COLLAB_AGENTS" ]; then
  echo "No collab config in task metadata"
  exit 0
fi

TASK_DESC=$(python3 -c "import json; m=json.load(open('$META')); print(m.get('task',''))" 2>/dev/null)

echo "🤝 Running collab session: mode=${COLLAB_MODE} agents=${COLLAB_AGENTS}"

cd "$SWARM_DIR/collab"
node collab-session.js \
  --task "$TASK_DESC" \
  --agents "$COLLAB_AGENTS" \
  --topic "$THREAD_ID" \
  --mode "$COLLAB_MODE"

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ Collab session completed"
  # Update metadata
  python3 -c "
import json
m = json.load(open('$META'))
m['collab_completed'] = True
json.dump(m, open('$META', 'w'), indent=2)
" 2>/dev/null
else
  echo "❌ Collab session failed (exit $EXIT_CODE)"
fi

exit $EXIT_CODE
