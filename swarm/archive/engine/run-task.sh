#!/bin/bash
# run-task.sh — The COMPLETE engine: plan → topic → spawn → verify → report
# Usage: run-task.sh "task description" [project_dir] [url]
# This is what the orchestrator calls. One command does everything.
set -euo pipefail

TASK="$1"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"
ENGINE_DIR="$(dirname "$0")"
SWARM_DIR="$(dirname "$ENGINE_DIR")"
MAX_RETRIES=3

# 1. Plan — determine agent and checks
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')
AGENT="koder"
case "$TASK_LOWER" in
  *עיצוב*|*design*|*css*|*ui*|*ux*) AGENT="tzayar" ;;
  *תרגום*|*translat*|*עברית*|*rtl*|*frontend*|*פרונט*) AGENT="front" ;;
  *בדיק*|*test*|*qa*) AGENT="tester" ;;
  *אבטח*|*secur*) AGENT="shomer" ;;
  *api*|*חיבור*|*connect*) AGENT="back" ;;
esac

# 2. Create Telegram topic
TOPIC_NAME="${TASK:0:50}"
THREAD=$(bash "$SWARM_DIR/create-topic.sh" "🔧 $TOPIC_NAME" "" "$AGENT" 2>/dev/null || echo "0")
echo "AGENT=$AGENT"
echo "THREAD=$THREAD"

# 3. Notify start
bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "🔄 מתחיל: $TASK" 2>/dev/null || true

# 4. Before screenshot
bash "$ENGINE_DIR/check.sh" screenshot "$URL" "/tmp/engine-before-${AGENT}-${THREAD}.png" 2>/dev/null || true

# 5. Build minimal prompt
PROMPT="You are agent $AGENT. Thread: $THREAD.

## Your ONE task:
$TASK

## Project: $PROJECT
## Live URL: $URL

## Rules:
1. Read the code, understand what needs to change
2. Make your changes
3. Test: curl -s -o /dev/null -w '%{http_code}' $URL (must be 200)
4. Screenshot:
node -e \"const p=require('puppeteer');(async()=>{const b=await p.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const g=await b.newPage();await g.setViewport({width:1280,height:800});await g.goto('$URL',{waitUntil:'networkidle2',timeout:60000});await new Promise(r=>setTimeout(r,3000));await g.screenshot({path:'/tmp/agent-$AGENT-final.png'});console.log('DONE');await b.close()})();\"
5. Commit: cd $PROJECT && git add -A && git commit -m '#$THREAD: done'
6. Done marker:
mkdir -p /tmp/engine-steps
echo 'done' > /tmp/engine-steps/$AGENT-$THREAD.done

DO THE WORK. No contracts, no reports, no protocols."

# Save prompt for orchestrator to use
mkdir -p /tmp/engine-tasks
echo "$PROMPT" > "/tmp/engine-tasks/${AGENT}-${THREAD}.prompt"

# 6. Output for orchestrator
echo "PROMPT_FILE=/tmp/engine-tasks/${AGENT}-${THREAD}.prompt"
echo "BEFORE_SCREENSHOT=/tmp/engine-before-${AGENT}-${THREAD}.png"
echo "DONE_MARKER=/tmp/engine-steps/${AGENT}-${THREAD}.done"
echo "AGENT_SCREENSHOT=/tmp/agent-${AGENT}-final.png"
echo "LABEL=${AGENT}-${THREAD}"
