#!/bin/bash
# auto-memory-recall.sh — Load topic context at session start
# Usage: auto-memory-recall.sh <topic_id>
# Returns: last context for this topic

TOPIC_ID="$1"
[ -z "$TOPIC_ID" ] && exit 0

MEMORY_DIR="/root/.openclaw/workspace/memory/topics"
TOPIC_FILE="$MEMORY_DIR/$TOPIC_ID.md"

if [ -f "$TOPIC_FILE" ]; then
  echo "=== TOPIC $TOPIC_ID CONTEXT ==="
  cat "$TOPIC_FILE"
  echo "=== END CONTEXT ==="
else
  # Try to extract from latest session transcript
  SESSIONS_DIR="/root/.openclaw/agents/main/sessions"
  LATEST=$(ls -t "$SESSIONS_DIR"/*topic-${TOPIC_ID}*.jsonl 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    echo "=== NO SAVED CONTEXT, LAST SESSION TRANSCRIPT ==="
    python3 -c "
import json
msgs = []
for line in open('$LATEST'):
    try:
        m = json.loads(line)
        if m.get('type') != 'message': continue
        msg = m.get('message', {})
        role = msg.get('role', '')
        if role not in ('user', 'assistant'): continue
        for c in msg.get('content', []):
            if c.get('type') == 'text':
                text = c['text'][:300]
                if role == 'user':
                    lines = text.split('\n')
                    clean = [l for l in lines if 'untrusted' not in l and 'conversation_label' not in l and 'json' not in l.strip()[:4]]
                    text = '\n'.join(clean).strip()
                if text and len(text) > 3:
                    msgs.append(f'{role}: {text}')
    except: pass
for m in msgs[-10:]:
    print(m)
" 2>/dev/null
    echo "=== END ==="
  fi
fi
