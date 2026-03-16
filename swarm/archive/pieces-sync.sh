#!/bin/bash
# Sync OpenClaw activity to Pieces LTM
# Run periodically via heartbeat/cron

DISPLAY=:1
PIECES_API="http://localhost:39300"

# Check Pieces is running
if ! curl -s "$PIECES_API/.well-known/health" | grep -q "ok"; then
  echo "❌ PiecesOS not running"
  exit 1
fi

# 1. Sync today's memory file
TODAY=$(date '+%Y-%m-%d')
MEMORY_FILE="/root/.openclaw/workspace/memory/${TODAY}.md"
if [ -f "$MEMORY_FILE" ]; then
  CONTENT=$(cat "$MEMORY_FILE" | head -100)
  echo "$CONTENT" | xclip -selection clipboard 2>/dev/null
  echo "y" | pieces --ignore-onboarding create 2>/dev/null
  echo "✅ Synced daily memory: $TODAY"
fi

# 2. Sync recent git commits (last 24h)
cd /root/.openclaw/workspace
COMMITS=$(git log --since="24 hours ago" --oneline 2>/dev/null | head -20)
if [ -n "$COMMITS" ]; then
  echo "// Git Activity - $TODAY
$COMMITS" | xclip -selection clipboard 2>/dev/null
  echo "y" | pieces --ignore-onboarding create 2>/dev/null
  echo "✅ Synced git commits"
fi

# 3. Sync recent task completions from swarm logs
LOGFILE="/root/.openclaw/workspace/swarm/logs/${TODAY}.jsonl"
if [ -f "$LOGFILE" ]; then
  TASKS=$(tail -20 "$LOGFILE" | python3 -c "
import sys,json
for line in sys.stdin:
  try:
    d=json.loads(line.strip())
    if d.get('text',''):
      print(f\"[{d.get('agent','?')}] {d['text'][:100]}\")
  except: pass
" 2>/dev/null)
  if [ -n "$TASKS" ]; then
    echo "// Agent Activity - $TODAY
$TASKS" | xclip -selection clipboard 2>/dev/null
    echo "y" | pieces --ignore-onboarding create 2>/dev/null
    echo "✅ Synced agent activity"
  fi
fi

# 4. Sync MEMORY.md changes (long-term context)
MEMORY_HASH_FILE="/tmp/pieces-memory-hash"
CURRENT_HASH=$(md5sum /root/.openclaw/workspace/MEMORY.md 2>/dev/null | cut -d' ' -f1)
LAST_HASH=$(cat "$MEMORY_HASH_FILE" 2>/dev/null)
if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
  cat /root/.openclaw/workspace/MEMORY.md | head -150 | xclip -selection clipboard 2>/dev/null
  echo "y" | pieces --ignore-onboarding create 2>/dev/null
  echo "$CURRENT_HASH" > "$MEMORY_HASH_FILE"
  echo "✅ Synced MEMORY.md update"
fi

echo "🧠 Pieces sync complete: $(date '+%H:%M')"
