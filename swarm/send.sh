#!/bin/bash
# Swarm Send v2 — Enhanced message delivery
# Usage: ./send.sh <agent_id> <thread_id> <message> [--photo path]
# Example: ./send.sh shomer 479 "בודק פורטים..."
# Example: ./send.sh koder 123 "תוצאה" --photo /tmp/screenshot.png

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="$1"
THREAD_ID="$2"
MESSAGE="$3"
PHOTO_FLAG="$4"
PHOTO_PATH="$5"

if [ -z "$AGENT_ID" ] || [ -z "$THREAD_ID" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_id> <thread_id> <message> [--photo path]"
  echo "Agents: or, shomer, koder, tzayar, worker, researcher"
  exit 1
fi

# Map agent to token file
case "$AGENT_ID" in
  or)      TOKEN_FILE="$SWARM_DIR/.bot-token" ;;
  shomer)  TOKEN_FILE="$SWARM_DIR/.shomer-token" ;;
  koder)   TOKEN_FILE="$SWARM_DIR/.koder-token" ;;
  tzayar)  TOKEN_FILE="$SWARM_DIR/.tzayar-token" ;;
  worker)     TOKEN_FILE="$SWARM_DIR/.worker-token" ;;
  researcher) TOKEN_FILE="$SWARM_DIR/.researcher-token" ;;
  *)          echo "Unknown agent: $AGENT_ID"; exit 1 ;;
esac

TOKEN=$(cat "$TOKEN_FILE")
CHAT_ID="-1003815143703"

# Send photo if requested
if [ "$PHOTO_FLAG" = "--photo" ] && [ -n "$PHOTO_PATH" ] && [ -f "$PHOTO_PATH" ]; then
  RESULT=$(curl -s "https://api.telegram.org/bot$TOKEN/sendPhoto" \
    -F "chat_id=$CHAT_ID" \
    -F "message_thread_id=$THREAD_ID" \
    -F "photo=@$PHOTO_PATH" \
    -F "caption=$MESSAGE" \
    -F "parse_mode=HTML")
else
  # Send text message
  RESULT=$(curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg chat "$CHAT_ID" --argjson thread "$THREAD_ID" --arg text "$MESSAGE" \
      '{chat_id: $chat, message_thread_id: $thread, text: $text, parse_mode: "HTML"}')")
fi

# Retry once on failure
OK=$(echo "$RESULT" | jq -r '.ok')
if [ "$OK" != "true" ]; then
  sleep 2
  if [ "$PHOTO_FLAG" = "--photo" ] && [ -n "$PHOTO_PATH" ] && [ -f "$PHOTO_PATH" ]; then
    RESULT=$(curl -s "https://api.telegram.org/bot$TOKEN/sendPhoto" \
      -F "chat_id=$CHAT_ID" \
      -F "message_thread_id=$THREAD_ID" \
      -F "photo=@$PHOTO_PATH" \
      -F "caption=$MESSAGE" \
      -F "parse_mode=HTML")
  else
    RESULT=$(curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg chat "$CHAT_ID" --argjson thread "$THREAD_ID" --arg text "$MESSAGE" \
        '{chat_id: $chat, message_thread_id: $thread, text: $text, parse_mode: "HTML"}')")
  fi
fi

# Log to file
LOG_DIR="$SWARM_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
MSG_ID=$(echo "$RESULT" | jq -r '.result.message_id // "error"')
OK=$(echo "$RESULT" | jq -r '.ok')
jq -n --arg ts "$(date -Iseconds)" --arg agent "$AGENT_ID" --argjson thread "$THREAD_ID" \
  --arg msg "$MESSAGE" --arg msg_id "$MSG_ID" --arg ok "$OK" \
  '{timestamp: $ts, agent: $agent, thread: $thread, message: $msg, message_id: $msg_id, ok: $ok}' >> "$LOG_FILE"

echo "$RESULT"
