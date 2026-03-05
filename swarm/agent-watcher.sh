#!/bin/bash
# agent-watcher.sh — Monitors completed agents, sends Telegram notifications
# Runs every minute via system crontab
# Method 1: done-markers in /tmp/agent-done/
# Method 2: OpenClaw hooks API for sub-agent completion

DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
SEEN_FILE="/tmp/agent-watcher-seen.txt"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"
touch "$SEEN_FILE"

OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
DEFAULT_TOPIC="4950"

send_telegram() {
  local topic="$1"
  local msg="$2"
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "message_thread_id=${topic}" \
    -d "text=${msg}" > /dev/null 2>&1
}

# Method 1: Check done-markers
for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue
  
  label=$(python3 -c "import json;print(json.load(open('$f')).get('label','unknown'))" 2>/dev/null)
  topic=$(python3 -c "import json;print(json.load(open('$f')).get('topic','$DEFAULT_TOPIC'))" 2>/dev/null)
  summary=$(python3 -c "import json;print(json.load(open('$f')).get('summary','done'))" 2>/dev/null)
  
  send_telegram "$topic" "🤖 סוכן ${label} סיים: ${summary}"
  
  cp "$f" "$REPORTED_DIR/$base"
  rm "$f"
  echo "$(date -Iseconds) Marker: $label → topic $topic"
done

# Method 2: Check OpenClaw sub-agent sessions via hooks API
HOOK_TOKEN=$(grep -oP '"token"\s*:\s*"([^"]+)"' ~/.openclaw/openclaw.json 2>/dev/null | head -1 | grep -oP '"[^"]+"\s*$' | tr -d '"' | tr -d ' ')
GATEWAY_PORT=$(python3 -c "import json;print(json.load(open('$HOME/.openclaw/openclaw.json')).get('gateway',{}).get('port',18789))" 2>/dev/null)

if [ -n "$HOOK_TOKEN" ] && [ "$HOOK_TOKEN" != "__OPENCLAW_REDACTED__" ]; then
  # Try to get recent sessions via API
  RESPONSE=$(curl -s -H "Authorization: Bearer $HOOK_TOKEN" \
    "http://localhost:${GATEWAY_PORT}/api/sessions?activeMinutes=5" 2>/dev/null)
  
  if [ -n "$RESPONSE" ]; then
    # Parse sub-agent completions
    python3 -c "
import json, sys
try:
    data = json.loads('''$RESPONSE''')
    seen = set(open('$SEEN_FILE').read().splitlines()) if True else set()
    for s in data.get('sessions', []):
        key = s.get('sessionKey', '')
        if 'subagent' in key and s.get('status') == 'done':
            rid = s.get('runId', key)
            if rid not in seen:
                label = s.get('label', 'unknown')
                print(f'{label}|done')
                with open('$SEEN_FILE', 'a') as f:
                    f.write(rid + '\n')
except:
    pass
" 2>/dev/null | while IFS='|' read label status; do
      send_telegram "$DEFAULT_TOPIC" "🤖 סוכן ${label} סיים (auto-detected)"
      echo "$(date -Iseconds) API: $label → topic $DEFAULT_TOPIC"
    done
  fi
fi
