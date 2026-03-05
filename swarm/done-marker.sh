#!/bin/bash
# Usage: bash done-marker.sh <label> <topic_id> "summary"
mkdir -p /tmp/agent-done
echo "{\"label\":\"$1\",\"topic\":\"$2\",\"summary\":\"$3\",\"timestamp\":\"$(date -Iseconds)\",\"reported\":false}" > /tmp/agent-done/$1.json
