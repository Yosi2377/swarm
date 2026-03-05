#!/bin/bash
# spawn-and-watch.sh — Wrapper that creates done-marker AFTER sub-agent finishes
# Usage: spawn-and-watch.sh <label> <topic> <summary>
# Called AFTER sessions_spawn — monitors until agent finishes, then creates marker

LABEL="${1:?Usage: spawn-and-watch.sh <label> <topic> <summary>}"
TOPIC="${2:-4950}"
SUMMARY="${3:-Agent completed}"

# Wait up to 10 minutes for the agent to finish
# Check every 15 seconds
for i in $(seq 1 40); do
  sleep 15
  
  # Check if done-marker already exists (agent was well-behaved)
  if [ -f "/tmp/agent-done/${LABEL}.json" ]; then
    echo "$(date) Agent created its own marker"
    exit 0
  fi
  
  # Check if marker was already reported
  if [ -f "/tmp/agent-done/reported/${LABEL}.json" ]; then
    echo "$(date) Already reported"
    exit 0
  fi
done

# If we got here, agent probably finished without creating marker
# Create it ourselves
bash /root/.openclaw/workspace/swarm/done-marker.sh "$LABEL" "$TOPIC" "$SUMMARY"
echo "$(date) Created marker for $LABEL (agent didn't create one)"
