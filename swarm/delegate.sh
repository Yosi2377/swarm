#!/bin/bash
# delegate.sh — Agent-to-Agent Delegation Queue
# Usage: delegate.sh FROM_AGENT TO_AGENT "TASK_DESCRIPTION"

FROM="$1"
TO="$2"
DESC="$3"

if [ -z "$FROM" ] || [ -z "$TO" ] || [ -z "$DESC" ]; then
  echo "Usage: delegate.sh FROM_AGENT TO_AGENT \"TASK_DESCRIPTION\""
  exit 1
fi

mkdir -p /tmp/delegate-queue

TIMESTAMP=$(date +%s%N | cut -c1-13)
ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILE="/tmp/delegate-queue/REQ-${TIMESTAMP}.json"

cat > "$FILE" <<EOF
{"from":"${FROM}","to":"${TO}","task":"${DESC}","status":"pending","created":"${ISO}"}
EOF

echo "✅ Delegation saved: $FILE"

# Notify Agent Chat (topic 479)
/root/.openclaw/workspace/swarm/send.sh "$FROM" 479 "🔄 ${FROM} מבקש עזרה מ-${TO}: ${DESC}"
