#!/bin/bash
# check-delegations.sh — Show pending delegation requests

QUEUE_DIR="/tmp/delegate-queue"

if [ ! -d "$QUEUE_DIR" ] || [ -z "$(ls -A "$QUEUE_DIR" 2>/dev/null)" ]; then
  echo "📭 No delegation requests found."
  exit 0
fi

echo "📋 Pending Delegation Requests:"
echo "================================"

for f in "$QUEUE_DIR"/*.json; do
  STATUS=$(python3 -c "import json;d=json.load(open('$f'));print(d.get('status','?'))" 2>/dev/null)
  if [ "$STATUS" = "pending" ]; then
    python3 -c "
import json
d=json.load(open('$f'))
print(f\"  📄 $(basename $f)\")
print(f\"     From: {d['from']} → To: {d['to']}\")
print(f\"     Task: {d['task']}\")
print(f\"     Created: {d['created']}\")
print()
" 2>/dev/null
  fi
done
