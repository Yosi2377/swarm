#!/bin/bash
# agent-watcher.sh — Zero-token background watcher
# Polls /tmp/agent-done/ every 20s, sends Telegram when agent finishes
# Usage: agent-watcher.sh [poll_seconds]

POLL="${1:-20}"
DONE_DIR="/tmp/agent-done"
CHAT_ID="-1003815143703"
TOKEN=$(cat "$(dirname "$0")/.bot-token" 2>/dev/null)

mkdir -p "$DONE_DIR"

send_tg() {
  local thread="$1"
  local msg="$2"
  curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$CHAT_ID\",\"message_thread_id\":$thread,\"text\":\"$msg\"}" >/dev/null 2>&1
}

echo "👁️ Agent Watcher started (poll every ${POLL}s)"
echo "📂 Watching: $DONE_DIR"

while true; do
  for f in "$DONE_DIR"/*.json; do
    [ -f "$f" ] || continue
    
    # Read marker
    THREAD=$(python3 -c "import json;print(json.load(open('$f')).get('thread',1))" 2>/dev/null || echo "1")
    STATUS=$(python3 -c "import json;print(json.load(open('$f')).get('status','done'))" 2>/dev/null || echo "done")
    MSG=$(python3 -c "import json;print(json.load(open('$f')).get('message','סוכן סיים עבודה'))" 2>/dev/null || echo "סוכן סיים עבודה")
    AGENT=$(python3 -c "import json;print(json.load(open('$f')).get('agent','or'))" 2>/dev/null || echo "or")
    
    # Pick emoji
    case "$STATUS" in
      success) EMOJI="✅" ;;
      failed)  EMOJI="❌" ;;
      stuck)   EMOJI="🆘" ;;
      progress) EMOJI="⏳" ;;
      *)       EMOJI="📢" ;;
    esac
    
    # Send notification
    send_tg "$THREAD" "${EMOJI} ${MSG}"
    echo "$(date +%H:%M:%S) → Sent to thread $THREAD: $MSG"
    
    # Remove marker
    rm -f "$f"
  done
  
  sleep "$POLL"
done
