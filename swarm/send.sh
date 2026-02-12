#!/bin/bash
# Usage: ./send.sh <agent_id> <thread_id> <message>
# Example: ./send.sh shomer 479 "בודק פורטים..."
#
# Also logs every message to swarm/logs/YYYY-MM-DD.jsonl

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="$1"
THREAD_ID="$2"
MESSAGE="$3"

if [ -z "$AGENT_ID" ] || [ -z "$THREAD_ID" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_id> <thread_id> <message>"
  echo "Agents: or, shomer, koder, tzayar, worker"
  exit 1
fi

# Map agent to token file
case "$AGENT_ID" in
  or)      TOKEN_FILE="$SWARM_DIR/.bot-token" ;;
  shomer)  TOKEN_FILE="$SWARM_DIR/.shomer-token" ;;
  koder)   TOKEN_FILE="$SWARM_DIR/.koder-token" ;;
  tzayar)  TOKEN_FILE="$SWARM_DIR/.tzayar-token" ;;
  worker)  TOKEN_FILE="$SWARM_DIR/.worker-token" ;;
  *)       echo "Unknown agent: $AGENT_ID"; exit 1 ;;
esac

TOKEN=$(cat "$TOKEN_FILE")
CHAT_ID="-1003815143703"

# Send message
RESULT=$(curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg chat "$CHAT_ID" --argjson thread "$THREAD_ID" --arg text "$MESSAGE" \
    '{chat_id: $chat, message_thread_id: $thread, text: $text, parse_mode: "HTML"}')")

# Log to file
LOG_FILE="$SWARM_DIR/logs/$(date +%Y-%m-%d).jsonl"
MSG_ID=$(echo "$RESULT" | jq -r '.result.message_id // "error"')
jq -n --arg ts "$(date -Iseconds)" --arg agent "$AGENT_ID" --argjson thread "$THREAD_ID" \
  --arg msg "$MESSAGE" --arg msg_id "$MSG_ID" \
  '{timestamp: $ts, agent: $agent, thread: $thread, message: $msg, message_id: $msg_id}' >> "$LOG_FILE"

echo "$RESULT"
