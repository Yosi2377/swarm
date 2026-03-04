#!/bin/bash
# agent-watcher.sh — Zero-token background watcher
# Polls /tmp/agent-done/ every 20s, sends Telegram when agent finishes
# Usage: agent-watcher.sh [poll_seconds]

POLL="${1:-5}"
DONE_DIR="/tmp/agent-done"
CHAT_ID="-1003815143703"
TOKEN=$(cat "$(dirname "$0")/.bot-token" 2>/dev/null)

mkdir -p "$DONE_DIR"

send_tg() {
  local thread="$1"
  local msg="$2"
  local agent="$3"
  # Use the agent's own bot token
  local SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
  local AGENT_TOKEN=""
  case "$agent" in
    koder)   AGENT_TOKEN=$(cat "$SWARM_DIR/.koder-token" 2>/dev/null) ;;
    shomer)  AGENT_TOKEN=$(cat "$SWARM_DIR/.shomer-token" 2>/dev/null) ;;
    tzayar)  AGENT_TOKEN=$(cat "$SWARM_DIR/.tzayar-token" 2>/dev/null) ;;
    worker)  AGENT_TOKEN=$(cat "$SWARM_DIR/.worker-token" 2>/dev/null) ;;
    *)       AGENT_TOKEN="$TOKEN" ;;
  esac
  [ -z "$AGENT_TOKEN" ] && AGENT_TOKEN="$TOKEN"
  curl -sf "https://api.telegram.org/bot${AGENT_TOKEN}/sendMessage" \
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
    
    # Send notification to Telegram via the agent's own bot
    send_tg "$THREAD" "${EMOJI} ${MSG}" "$AGENT"
    echo "$(date +%H:%M:%S) → Sent to thread $THREAD: $MSG"
    
    # Inject into THIS topic's session so Or replies to Yossi there
    curl -sf -X POST "http://127.0.0.1:18789/hooks/agent" \
      -H "Authorization: Bearer agent-watcher-wake-2026" \
      -H "Content-Type: application/json" \
      -d "{\"message\":\"[System] סוכן ${AGENT} סיים עבודה (${STATUS}) בנושא ${THREAD}. ההודעה: ${MSG}. עדכן את יוסי בנושא הזה עכשיו.\",\"sessionKey\":\"agent:main:telegram:group:-1003815143703:topic:${THREAD}\"}" >/dev/null 2>&1 || true
    echo "$(date +%H:%M:%S) → Agent hook sent to topic ${THREAD} session"
    
    # Remove marker
    rm -f "$f"
  done
  
  sleep "$POLL"
done
