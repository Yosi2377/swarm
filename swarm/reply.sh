#!/bin/bash
# Usage: ./reply.sh <agent_id> <thread_id> <reply_to_message_id> <message>
# Sends a reply to a specific message (creates a conversation thread)

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="$1"
THREAD_ID="$2"
REPLY_TO="$3"
MESSAGE="$4"

if [ -z "$REPLY_TO" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_id> <thread_id> <reply_to_msg_id> <message>"
  exit 1
fi

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

RESULT=$(curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg chat "$CHAT_ID" --argjson thread "$THREAD_ID" \
    --argjson reply "$REPLY_TO" --arg text "$MESSAGE" \
    '{chat_id: $chat, message_thread_id: $thread, reply_to_message_id: $reply, text: $text, parse_mode: "HTML"}')")

# Log
LOG_FILE="$SWARM_DIR/logs/$(date +%Y-%m-%d).jsonl"
MSG_ID=$(echo "$RESULT" | jq -r '.result.message_id // "error"')
jq -n --arg ts "$(date -Iseconds)" --arg agent "$AGENT_ID" --argjson thread "$THREAD_ID" \
  --argjson reply "$REPLY_TO" --arg msg "$MESSAGE" --arg msg_id "$MSG_ID" \
  '{timestamp: $ts, agent: $agent, thread: $thread, reply_to: $reply, message: $msg, message_id: $msg_id}' >> "$LOG_FILE"

echo "$RESULT"
