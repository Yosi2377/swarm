#!/bin/bash
# spawn-with-watch.sh — Background watcher for a specific sub-agent
# Usage: spawn-with-watch.sh <label> <topic> <summary>
# Polls every 15 seconds to check if sub-agent finished
# Creates done-marker when it detects completion

LABEL="${1:?Usage: spawn-with-watch.sh <label> <topic> <summary>}"
TOPIC="${2:-4950}"
SUMMARY="${3:-Agent completed}"
HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
GATEWAY_PORT=18789

echo "$(date) Watching for $LABEL completion..." >> /tmp/agent-watcher.log

for i in $(seq 1 80); do  # 80 * 15s = 20 minutes max
  sleep 15
  
  # Check if marker already exists
  [ -f "/tmp/agent-done/${LABEL}.json" ] && exit 0
  [ -f "/tmp/agent-done/reported/${LABEL}.json" ] && exit 0
  
  # Check via OpenClaw tools/invoke API if sub-agent finished
  RESULT=$(curl -s -X POST "http://localhost:${GATEWAY_PORT}/tools/invoke" \
    -H "Authorization: Bearer $(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('gateway',{}).get('auth',{}).get('token',''))")" \
    -H "Content-Type: application/json" \
    -d '{"tool":"subagents","args":{"action":"list","recentMinutes":30}}' 2>/dev/null)
  
  # Check if our label shows as "done"
  IS_DONE=$(echo "$RESULT" | python3 -c "
import json,sys
try:
  data = json.load(sys.stdin)
  text = data.get('result',{}).get('details',{}).get('text','')
  for line in text.split('\n'):
    if '${LABEL}' in line and 'done' in line:
      print('yes')
      break
except: pass
" 2>/dev/null)
  
  if [ "$IS_DONE" = "yes" ]; then
    echo "$(date) Detected $LABEL completed!" >> /tmp/agent-watcher.log
    bash /root/.openclaw/workspace/swarm/done-marker.sh "$LABEL" "$TOPIC" "$SUMMARY"
    # Watcher crontab will pick it up within 1 minute
    exit 0
  fi
done

echo "$(date) Timeout watching $LABEL" >> /tmp/agent-watcher.log
