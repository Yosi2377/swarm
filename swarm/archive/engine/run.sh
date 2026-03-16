#!/bin/bash
# run.sh — Main engine pipeline: prepare everything, output JSON for caller
# Usage: run.sh "task description" [project_dir] [url]
# Output: JSON with agent, thread, prompt, checks, etc.
set -euo pipefail

TASK="${1:?Usage: run.sh 'task description' [project_dir] [url]}"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
SWARM_DIR="$(dirname "$ENGINE_DIR")"

mkdir -p /tmp/engine-tasks /tmp/engine-steps

# 1. Classify agent
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')
AGENT="koder"
case "$TASK_LOWER" in
  *עיצוב*|*design*|*css*|*ui*|*ux*|*לוגו*) AGENT="tzayar" ;;
  *תרגום*|*translat*|*עברית*|*rtl*|*frontend*|*פרונט*|*html*) AGENT="front" ;;
  *בדיק*|*test*|*qa*) AGENT="tester" ;;
  *אבטח*|*secur*) AGENT="shomer" ;;
  *api*|*backend*|*server*|*express*) AGENT="back" ;;
  *docker*|*container*|*devops*) AGENT="docker" ;;
  *data*|*mongo*|*sql*|*דאטא*) AGENT="data" ;;
  *debug*|*דיבאג*|*error*) AGENT="debugger" ;;
  *monitor*|*alert*|*uptime*) AGENT="monitor" ;;
  *refactor*|*tech.debt*) AGENT="refactor" ;;
  *perform*|*cache*|*optim*) AGENT="optimizer" ;;
esac

# 2. Query lessons
LESSONS=$(bash "$ENGINE_DIR/learn.sh" inject "$AGENT" "$TASK" 2>/dev/null || echo "")

# 3. Generate checks
CHECKS=$(bash "$ENGINE_DIR/smart-check.sh" "$TASK" "$PROJECT" "$URL" 2>/dev/null || echo "http_status $URL 200")

# 4. Create Telegram topic
TOPIC_NAME="${TASK:0:50}"
THREAD=$(bash "$SWARM_DIR/create-topic.sh" "🔧 $TOPIC_NAME" "" "$AGENT" 2>/dev/null | grep -o '[0-9]*' | tail -1 || echo "0")

# 5. Before screenshot
bash "$ENGINE_DIR/check.sh" screenshot "$URL" "/tmp/engine-before-${AGENT}-${THREAD}.png" >/dev/null 2>&1 || true

# 6. Build prompt
PROMPT_FILE="/tmp/engine-tasks/${AGENT}-${THREAD}.prompt"
cat > "$PROMPT_FILE" << PROMPT
You are agent $AGENT. Thread: $THREAD.

## Task:
$TASK

## Project: $PROJECT
## URL: $URL
${LESSONS:+
$LESSONS
}
## Rules:
1. Read the code, understand it, make changes
2. Verify: curl -s -o /dev/null -w '%{http_code}' $URL → must be 200
3. Screenshot after: node -e "const p=require('puppeteer');(async()=>{const b=await p.launch({headless:true,args:['--no-sandbox']});const g=await b.newPage();await g.setViewport({width:1280,height:800});await g.goto('$URL',{waitUntil:'networkidle2',timeout:60000});await new Promise(r=>setTimeout(r,3000));await g.screenshot({path:'/tmp/agent-${AGENT}-final.png'});await b.close()})();"
4. Commit: cd $PROJECT && git add -A && git commit -m 'engine: ${AGENT}-${THREAD} done'
5. Done marker: mkdir -p /tmp/engine-steps && echo done > /tmp/engine-steps/${AGENT}-${THREAD}.done

DO THE WORK. No questions. No clarifications. Just execute.
PROMPT

# Clean old done marker
rm -f "/tmp/engine-steps/${AGENT}-${THREAD}.done"

# Notify agent topic
bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "🔄 מתחיל: ${TASK:0:80}" >/dev/null 2>&1 || true

# 7. Output JSON
CHECKS_JSON=$(echo "$CHECKS" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
PROMPT_JSON=$(python3 -c "import json; print(json.dumps(open('$PROMPT_FILE').read()))")

cat << EOF
{
  "agent": "$AGENT",
  "thread": "$THREAD",
  "prompt_file": "$PROMPT_FILE",
  "done_marker": "/tmp/engine-steps/${AGENT}-${THREAD}.done",
  "checks": $CHECKS_JSON,
  "label": "${AGENT}-${THREAD}",
  "max_retries": 3,
  "timeout_seconds": 300,
  "prompt": $PROMPT_JSON
}
EOF
