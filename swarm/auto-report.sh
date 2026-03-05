#!/bin/bash
# auto-report.sh — Report completed agents to orchestrator, mark as reported
# Reads /tmp/agent-done/, sends unreported completions via send.sh

DONE_DIR="/tmp/agent-done"
SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DONE_DIR"

for f in "$DONE_DIR"/*.json; do
  [ ! -f "$f" ] && continue

  # Check if already reported
  REPORTED=$(python3 -c "import json; print(json.load(open('$f')).get('reported', False))" 2>/dev/null)
  [ "$REPORTED" = "True" ] && continue

  # Extract fields
  LABEL=$(python3 -c "import json; print(json.load(open('$f')).get('label','?'))" 2>/dev/null)
  TOPIC=$(python3 -c "import json; print(json.load(open('$f')).get('topic','1'))" 2>/dev/null)
  AGENT=$(python3 -c "import json; print(json.load(open('$f')).get('agent','worker'))" 2>/dev/null)
  SUMMARY=$(python3 -c "import json; print(json.load(open('$f')).get('summary','No summary')[:300])" 2>/dev/null)
  STATUS=$(python3 -c "import json; print(json.load(open('$f')).get('status','done'))" 2>/dev/null)

  # Report to General (topic 1)
  bash "$SWARM_DIR/send.sh" or 1 "📋 סוכן סיים: $LABEL
סטטוס: $STATUS
סיכום: $SUMMARY"

  # Mark as reported
  python3 -c "
import json
d = json.load(open('$f'))
d['reported'] = True
json.dump(d, open('$f','w'))
" 2>/dev/null

  echo "[auto-report] Reported: $LABEL"
done
