#!/bin/bash
# Ask-help — Inter-agent help requests
# Usage: ask-help.sh <from-agent> <to-agent> <thread-id> "description"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SWARM_DIR/logs"
QUEUE_DIR="/tmp/delegate-queue"

FROM="$1"
TO="$2"
THREAD="$3"
DESC="$4"

if [ -z "$FROM" ] || [ -z "$TO" ] || [ -z "$THREAD" ] || [ -z "$DESC" ]; then
  echo "Usage: $0 <from-agent> <to-agent> <thread-id> \"description\""
  echo "Example: $0 koder shomer 1234 \"Need security review for auth module\""
  echo "Agents: or, shomer, koder, tzayar, worker, researcher, bodek"
  exit 1
fi

mkdir -p "$LOG_DIR" "$QUEUE_DIR"

TS=$(date -Is)

# Post to Agent Chat (topic 479)
"$SWARM_DIR/send.sh" "$FROM" 479 "🆘 <b>בקשת עזרה</b>
מאת: $FROM
אל: $TO
Thread: $THREAD
📝 $DESC"

# Create delegate queue entry
cat > "$QUEUE_DIR/${TO}-help.json" <<EOF
{"type":"help","from":"$FROM","to":"$TO","thread_id":"$THREAD","description":"$DESC","ts":"$TS"}
EOF

# Log
echo "$TS | $FROM → $TO | thread:$THREAD | $DESC" >> "$LOG_DIR/help-requests.log"

echo "✅ Help request sent from $FROM to $TO (thread $THREAD)"
