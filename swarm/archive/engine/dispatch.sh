#!/bin/bash
# dispatch.sh — Prepares full-run context for OpenClaw orchestrator to spawn
# Usage: dispatch.sh "task" [project] [url]
# Output: everything OpenClaw needs to run full-run.sh with sessions_spawn
set -euo pipefail

TASK="$1"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"
ENGINE_DIR="$(dirname "$0")"

# Classify agent
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')
AGENT="koder"
case "$TASK_LOWER" in
  *עיצוב*|*design*|*css*|*ui*|*ux*) AGENT="tzayar" ;;
  *תרגום*|*translat*|*עברית*|*rtl*|*frontend*|*פרונט*|*html*) AGENT="front" ;;
  *בדיק*|*test*|*qa*) AGENT="tester" ;;
  *אבטח*|*secur*) AGENT="shomer" ;;
  *api*|*חיבור*|*connect*|*backend*) AGENT="back" ;;
  *מפה*|*map*|*geo*) AGENT="front" ;;
esac

# Get lessons
LESSONS=$(bash "$ENGINE_DIR/learn.sh" inject "$AGENT" "$TASK" 2>/dev/null || echo "")

# Create topic
TOPIC_NAME="${TASK:0:50}"
THREAD=$(bash "$(dirname "$ENGINE_DIR")/create-topic.sh" "🔧 $TOPIC_NAME" "" "$AGENT" 2>/dev/null | grep -o '[0-9]*' | tail -1 || echo "0")

# Before screenshot
bash "$ENGINE_DIR/check.sh" screenshot "$URL" "/tmp/engine-before-${AGENT}-${THREAD}.png" 2>/dev/null || true

# Build prompt
PROMPT="You are agent $AGENT. Thread: $THREAD.

## Task:
$TASK

## Project: $PROJECT
## URL: $URL

$LESSONS

## Rules:
1. Read code, make changes
2. Verify: curl -s -o /dev/null -w '%{http_code}' $URL (must be 200)
3. Screenshot: node -e \"const p=require('puppeteer');(async()=>{const b=await p.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const g=await b.newPage();await g.setViewport({width:1280,height:800});await g.goto('$URL',{waitUntil:'networkidle2',timeout:60000});await new Promise(r=>setTimeout(r,3000));await g.screenshot({path:'/tmp/agent-${AGENT}-final.png'});await b.close()})();\"
4. Commit: cd $PROJECT && git add -A && git commit -m 'engine: $AGENT-$THREAD done'
5. Done: mkdir -p /tmp/engine-steps && echo done > /tmp/engine-steps/${AGENT}-${THREAD}.done

DO THE WORK."

PROMPT_FILE="/tmp/engine-tasks/${AGENT}-${THREAD}.prompt"
mkdir -p /tmp/engine-tasks /tmp/engine-steps
echo "$PROMPT" > "$PROMPT_FILE"

# Clean old done marker
rm -f "/tmp/engine-steps/${AGENT}-${THREAD}.done"

# Notify
bash "$(dirname "$ENGINE_DIR")/send.sh" "$AGENT" "$THREAD" "🔄 מתחיל: ${TASK:0:80}" 2>/dev/null || true

# Output JSON for caller
cat << EOF
{
  "agent": "$AGENT",
  "thread": "$THREAD",
  "prompt_file": "$PROMPT_FILE",
  "check": "http_status $URL 200",
  "done_marker": "/tmp/engine-steps/${AGENT}-${THREAD}.done",
  "before_screenshot": "/tmp/engine-before-${AGENT}-${THREAD}.png",
  "label": "${AGENT}-${THREAD}",
  "prompt": $(python3 -c "import json; print(json.dumps(open('$PROMPT_FILE').read()))")
}
EOF
