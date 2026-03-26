#!/bin/bash
# auto-memory-save.sh — Extract and save session context automatically
# Called by cron every 30 min OR on session end
# Scans recent session transcripts and saves topic summaries

MEMORY_DIR="/root/.openclaw/workspace/memory/topics"
SESSIONS_DIR="/root/.openclaw/agents/main/sessions"
mkdir -p "$MEMORY_DIR"

# Find sessions modified in last hour
find "$SESSIONS_DIR" -name "*.jsonl" -mmin -60 -type f | while read f; do
  # Extract topic ID from filename
  TOPIC=$(echo "$f" | grep -o 'topic-[0-9]*' | grep -o '[0-9]*')
  [ -z "$TOPIC" ] && continue
  
  # Get last 5 user messages (actual content, not metadata)
  LAST_MSGS=$(python3 -c "
import sys, json
msgs = []
for line in open('$f'):
    try:
        m = json.loads(line)
        if m.get('type') != 'message': continue
        msg = m.get('message', {})
        role = msg.get('role', '')
        if role not in ('user', 'assistant'): continue
        for c in msg.get('content', []):
            if c.get('type') == 'text':
                text = c['text']
                # Strip metadata from user messages
                if role == 'user':
                    lines = text.split('\n')
                    clean = [l for l in lines if not any(x in l for x in ['untrusted', 'conversation_label', 'group_subject', 'is_forum', 'Conversation info', 'Sender', '\`\`\`json', '\`\`\`', '{', '}', '\"label\"', '\"name\"'])]
                    text = '\n'.join(clean).strip()
                if text and len(text) > 3:
                    msgs.append(f'{role}: {text[:200]}')
    except: pass
for m in msgs[-10:]:
    print(m)
" 2>/dev/null)
  
  [ -z "$LAST_MSGS" ] && continue
  
  # Save to topic file
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
  TOPIC_FILE="$MEMORY_DIR/$TOPIC.md"
  
  # Append latest context
  echo "" >> "$TOPIC_FILE"
  echo "## Session $TIMESTAMP" >> "$TOPIC_FILE"
  echo "$LAST_MSGS" >> "$TOPIC_FILE"
  
  # Keep file under 200 lines (trim old)
  LINES=$(wc -l < "$TOPIC_FILE")
  if [ "$LINES" -gt 200 ]; then
    tail -150 "$TOPIC_FILE" > "${TOPIC_FILE}.tmp"
    mv "${TOPIC_FILE}.tmp" "$TOPIC_FILE"
  fi
done

echo "Memory save complete: $(date)"
