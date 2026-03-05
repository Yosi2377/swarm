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
  echo "Agents: or, shomer, koder, tzayar, worker, researcher, bodek, data, debugger, docker, front, back, tester, refactor, monitor, optimizer, integrator"
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
  bodek)      TOKEN_FILE="$SWARM_DIR/.bodek-token" ;;
  data)       TOKEN_FILE="$SWARM_DIR/.data-token" ;;
  debugger)   TOKEN_FILE="$SWARM_DIR/.debugger-token" ;;
  docker)     TOKEN_FILE="$SWARM_DIR/.docker-token" ;;
  front)      TOKEN_FILE="$SWARM_DIR/.front-token" ;;
  back)       TOKEN_FILE="$SWARM_DIR/.back-token" ;;
  tester)     TOKEN_FILE="$SWARM_DIR/.tester-token" ;;
  refactor)   TOKEN_FILE="$SWARM_DIR/.refactor-token" ;;
  monitor)    TOKEN_FILE="$SWARM_DIR/.monitor-token" ;;
  optimizer)  TOKEN_FILE="$SWARM_DIR/.optimizer-token" ;;
  integrator) TOKEN_FILE="$SWARM_DIR/.integrator-token" ;;
  *)          echo "Unknown agent: $AGENT_ID"; exit 1 ;;
esac

TOKEN=$(cat "$TOKEN_FILE")
CHAT_ID="-1003815143703"

# Build thread args — omit message_thread_id for General (thread=1) in forum groups
THREAD_FORM_ARGS=()
THREAD_JSON_EXTRA=""
if [ "$THREAD_ID" != "1" ]; then
  THREAD_FORM_ARGS=(-F "message_thread_id=$THREAD_ID")
  THREAD_JSON_EXTRA=", \"message_thread_id\": $THREAD_ID"
fi

send_msg() {
  if [ "$PHOTO_FLAG" = "--photo" ] && [ -n "$PHOTO_PATH" ] && [ -f "$PHOTO_PATH" ]; then
    curl -s "https://api.telegram.org/bot$TOKEN/sendPhoto" \
      -F "chat_id=$CHAT_ID" \
      "${THREAD_FORM_ARGS[@]}" \
      -F "photo=@$PHOTO_PATH" \
      -F "caption=$MESSAGE" \
      -F "parse_mode=HTML"
  else
    curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\": \"$CHAT_ID\"$THREAD_JSON_EXTRA, \"text\": $(echo "$MESSAGE" | jq -Rs .), \"parse_mode\": \"HTML\"}"
  fi
}

# Send (with one retry on failure)
RESULT=$(send_msg)
OK=$(echo "$RESULT" | jq -r '.ok')
if [ "$OK" != "true" ]; then
  sleep 2
  RESULT=$(send_msg)
fi

# Log to file
LOG_DIR="$SWARM_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
MSG_ID=$(echo "$RESULT" | jq -r '.result.message_id // "error"')
OK=$(echo "$RESULT" | jq -r '.ok')
jq -cn --arg ts "$(date -Iseconds)" --arg agent "$AGENT_ID" --argjson thread "$THREAD_ID" \
  --arg msg "$MESSAGE" --arg msg_id "$MSG_ID" --arg ok "$OK" \
  '{timestamp: $ts, agent: $agent, thread: $thread, message: $msg, message_id: $msg_id, ok: $ok}' >> "$LOG_FILE"

# Create marker for agent-watcher if message contains completion keywords
if echo "$MESSAGE" | grep -qiE '✅|סיימתי|הושלמה|done|finished|מוכן'; then
  mkdir -p /tmp/agent-done
  MARKER_MSG=$(echo "$MESSAGE" | head -1 | cut -c1-120 | sed 's/["\]//g')
  echo "{\"thread\":$THREAD_ID,\"status\":\"success\",\"message\":\"$MARKER_MSG\",\"agent\":\"$AGENT_ID\"}" > "/tmp/agent-done/$(date +%s)-${AGENT_ID}.json" 2>/dev/null
fi

echo "$RESULT"
