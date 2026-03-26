#!/bin/bash
# memory-system.sh — Complete memory management for Or
# 
# SAVE mode: Extract key facts from a session and save to structured memory
# RECALL mode: Load all relevant context for a topic
# COMPACT mode: Summarize and compress old memory to save context window
#
# Usage:
#   memory-system.sh save <topic_id>     — Save current session context
#   memory-system.sh recall <topic_id>   — Load topic context  
#   memory-system.sh compact             — Compress old memories
#   memory-system.sh status              — Show memory stats

ACTION="${1:-status}"
TOPIC_ID="$2"
MEMORY_DIR="/root/.openclaw/workspace/memory"
TOPICS_DIR="$MEMORY_DIR/topics"
SESSIONS_DIR="/root/.openclaw/agents/main/sessions"

mkdir -p "$TOPICS_DIR"

case "$ACTION" in
  save)
    [ -z "$TOPIC_ID" ] && echo "Usage: memory-system.sh save <topic_id>" && exit 1
    
    # Find latest session for this topic
    LATEST=$(ls -t "$SESSIONS_DIR"/*topic-${TOPIC_ID}*.jsonl 2>/dev/null | head -1)
    [ -z "$LATEST" ] && echo "No session found for topic $TOPIC_ID" && exit 1
    
    # Extract user and assistant messages
    CONTEXT=$(python3 -c "
import json, sys
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
                text = c['text']
                if role == 'user':
                    # Clean metadata
                    lines = text.split('\n')
                    clean = []
                    skip = False
                    for l in lines:
                        ls = l.strip()
                        if ls.startswith('Conversation info') or ls.startswith('Sender') or ls == '\`\`\`json' or ls == '\`\`\`':
                            skip = True
                            continue
                        if skip and (ls.startswith('{') or ls.startswith('}') or ls.startswith('\"')):
                            continue
                        if skip and not ls.startswith('{') and not ls.startswith('\"'):
                            skip = False
                        if not skip and ls:
                            clean.append(ls)
                    text = ' '.join(clean)
                if text and len(text.strip()) > 3:
                    msgs.append({'role': role, 'text': text[:500]})
    except: pass

# Output last 15 messages
for m in msgs[-15:]:
    print(f\"{m['role'].upper()}: {m['text']}\")
" 2>/dev/null)

    TOPIC_FILE="$TOPICS_DIR/$TOPIC_ID.md"
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
    
    # Create or update topic file
    if [ ! -f "$TOPIC_FILE" ]; then
      echo "# Topic $TOPIC_ID" > "$TOPIC_FILE"
      echo "Created: $TIMESTAMP" >> "$TOPIC_FILE"
      echo "" >> "$TOPIC_FILE"
    fi
    
    echo "" >> "$TOPIC_FILE"
    echo "---" >> "$TOPIC_FILE"
    echo "## Session $TIMESTAMP" >> "$TOPIC_FILE"
    echo "$CONTEXT" >> "$TOPIC_FILE"
    
    # Keep under 300 lines
    LINES=$(wc -l < "$TOPIC_FILE")
    if [ "$LINES" -gt 300 ]; then
      # Keep header + last 200 lines
      HEAD=$(head -5 "$TOPIC_FILE")
      TAIL=$(tail -200 "$TOPIC_FILE")
      echo "$HEAD" > "$TOPIC_FILE"
      echo "...(older sessions trimmed)..." >> "$TOPIC_FILE"
      echo "$TAIL" >> "$TOPIC_FILE"
    fi
    
    echo "Saved to $TOPIC_FILE ($LINES lines)"
    ;;
    
  recall)
    [ -z "$TOPIC_ID" ] && echo "Usage: memory-system.sh recall <topic_id>" && exit 1
    
    TOPIC_FILE="$TOPICS_DIR/$TOPIC_ID.md"
    
    echo "====== MEMORY RECALL FOR TOPIC $TOPIC_ID ======"
    
    # 1. Topic-specific memory
    if [ -f "$TOPIC_FILE" ]; then
      echo "--- TOPIC CONTEXT ---"
      tail -60 "$TOPIC_FILE"
    fi
    
    # 2. Recent decisions from MEMORY.md
    echo ""
    echo "--- KEY FACTS (MEMORY.md) ---"
    grep -A2 "Status\|חשוב\|Critical\|⚠️\|Decision\|החלטה" "$MEMORY_DIR/../MEMORY.md" 2>/dev/null | head -20
    
    # 3. Yesterday + today daily logs
    TODAY=$(date '+%Y-%m-%d')
    YESTERDAY=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null)
    for D in "$YESTERDAY" "$TODAY"; do
      F="$MEMORY_DIR/$D.md"
      if [ -f "$F" ]; then
        echo ""
        echo "--- DAILY LOG $D ---"
        tail -30 "$F"
      fi
    done
    
    echo ""
    echo "====== END RECALL ======"
    ;;
    
  compact)
    echo "Compacting old memories..."
    # Merge daily logs older than 7 days into weekly summaries
    find "$MEMORY_DIR" -name "202*.md" -mtime +7 -not -name "*full*" | sort | while read f; do
      BASENAME=$(basename "$f" .md)
      LINES=$(wc -l < "$f")
      if [ "$LINES" -gt 50 ]; then
        # Keep only first 50 lines (summary)
        head -50 "$f" > "${f}.tmp"
        echo "" >> "${f}.tmp"
        echo "(compacted from $LINES lines)" >> "${f}.tmp"
        mv "${f}.tmp" "$f"
        echo "Compacted: $BASENAME ($LINES → 50 lines)"
      fi
    done
    echo "Done"
    ;;
    
  status)
    echo "=== MEMORY STATUS ==="
    echo "Topic files: $(ls "$TOPICS_DIR"/*.md 2>/dev/null | wc -l)"
    echo "Daily logs: $(ls "$MEMORY_DIR"/202*.md 2>/dev/null | wc -l)"
    echo "Total memory size: $(du -sh "$MEMORY_DIR" 2>/dev/null | cut -f1)"
    echo "MEMORY.md size: $(wc -l < "$MEMORY_DIR/../MEMORY.md" 2>/dev/null) lines"
    echo ""
    echo "Recent topics:"
    ls -lt "$TOPICS_DIR"/*.md 2>/dev/null | head -5
    echo ""
    echo "Pieces status: $(curl -sf http://localhost:39300/.well-known/health > /dev/null 2>&1 && echo 'RUNNING' || echo 'DOWN')"
    ;;
esac
