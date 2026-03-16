#!/bin/bash
# spawn-with-watch.sh — Wait for sub-agent by checking if its work is done
# Usage: spawn-with-watch.sh <label> <topic> <summary> [check_command]
# Creates done-marker after check_command succeeds or after timeout

LABEL="${1:?Usage: spawn-with-watch.sh <label> <topic> <summary> [check_cmd]}"
TOPIC="${2:-4950}"
SUMMARY="${3:-Agent completed}"
CHECK_CMD="${4:-echo ok}"

echo "$(date) Watching $LABEL..." >> /tmp/agent-watcher.log

# Wait 30 seconds for agent to start working
sleep 30

# Then check every 15 seconds if the work is done
for i in $(seq 1 40); do
  # Check if marker already exists
  [ -f "/tmp/agent-done/${LABEL}.json" ] && exit 0
  [ -f "/tmp/agent-done/reported/${LABEL}.json" ] && exit 0
  
  # Run the check command
  eval "$CHECK_CMD" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "$(date) $LABEL check passed, creating marker" >> /tmp/agent-watcher.log
    bash /root/.openclaw/workspace/swarm/done-marker.sh "$LABEL" "$TOPIC" "$SUMMARY"
    exit 0
  fi
  
  sleep 15
done

# Timeout — create marker anyway so watcher picks it up
echo "$(date) $LABEL timeout, creating marker" >> /tmp/agent-watcher.log
bash /root/.openclaw/workspace/swarm/done-marker.sh "$LABEL" "$TOPIC" "$SUMMARY (timeout)"
