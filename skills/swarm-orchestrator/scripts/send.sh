#!/bin/bash
# send.sh — Send message as a specific bot agent to a Telegram forum topic
# Usage: send.sh <agent_id> <thread_id> "message"
# Agents: or, shomer, koder, tzayar, worker, researcher, bodek

SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT="$1"; THREAD="$2"; shift 2; MSG="$*"

case "$AGENT" in
  or)      TOKEN_FILE="$SWARM_DIR/.bot-token" ;;
  shomer)  TOKEN_FILE="$SWARM_DIR/.shomer-token" ;;
  koder)   TOKEN_FILE="$SWARM_DIR/.koder-token" ;;
  tzayar)  TOKEN_FILE="$SWARM_DIR/.tzayar-token" ;;
  worker)  TOKEN_FILE="$SWARM_DIR/.worker-token" ;;
  researcher) TOKEN_FILE="$SWARM_DIR/.researcher-token" ;;
  bodek)   TOKEN_FILE="$SWARM_DIR/.bodek-token" ;;
  *) echo "Unknown agent: $AGENT"; exit 1 ;;
esac

[ ! -f "$TOKEN_FILE" ] && echo "Token file missing: $TOKEN_FILE" && exit 1
TOKEN=$(cat "$TOKEN_FILE")
CHAT_ID="${TELEGRAM_CHAT_ID:--1003815143703}"

curl -s "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d message_thread_id="$THREAD" \
  -d parse_mode=HTML \
  -d disable_web_page_preview=true \
  --data-urlencode "text=$MSG"
