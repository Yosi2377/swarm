#!/bin/bash
# loop.sh — The core engine: run agent → check → retry → report
# Usage: loop.sh <agent_id> <thread_id> <task_json_file>
# task_json format:
# {
#   "task": "description",
#   "project": "/path/to/project",
#   "steps": [
#     {"prompt": "do X", "check": "http_status http://localhost:3200 200"},
#     {"prompt": "do Y", "check": "screenshot http://localhost:3200 /tmp/result.png"}
#   ],
#   "url": "http://localhost:3200"
# }
set -euo pipefail

AGENT="$1"
THREAD="$2"
TASK_FILE="$3"
MAX_RETRIES=3
ENGINE_DIR="$(dirname "$0")"
SWARM_DIR="$(dirname "$ENGINE_DIR")"

# Parse task JSON
TASK=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); print(d['task'])")
PROJECT=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); print(d.get('project','.'))")
URL=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); print(d.get('url',''))")
STEP_COUNT=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); print(len(d.get('steps',[])))")

echo "🔄 Engine starting: $AGENT on thread $THREAD"
echo "📋 Task: $TASK"
echo "📁 Project: $PROJECT"
echo "🔗 URL: $URL"
echo "📊 Steps: $STEP_COUNT"

# Notify Telegram
bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "🔄 מתחיל: $TASK ($STEP_COUNT שלבים)" 2>/dev/null || true

# Before screenshot
if [ -n "$URL" ]; then
  bash "$ENGINE_DIR/check.sh" screenshot "$URL" "/tmp/engine-before-${AGENT}-${THREAD}.png" 2>/dev/null || true
fi

PASSED=0
FAILED=0

for i in $(seq 0 $((STEP_COUNT - 1))); do
  STEP_PROMPT=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); print(d['steps'][$i]['prompt'])")
  STEP_CHECK=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); print(d['steps'][$i].get('check',''))")
  
  echo ""
  echo "═══════════════════════════════════════"
  echo "📌 Step $((i+1))/$STEP_COUNT: $STEP_PROMPT"
  echo "🔍 Check: $STEP_CHECK"
  echo "═══════════════════════════════════════"
  
  ATTEMPT=0
  STEP_PASSED=false
  LAST_ERROR=""
  
  while [ $ATTEMPT -lt $MAX_RETRIES ] && [ "$STEP_PASSED" = false ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "🔄 Attempt $ATTEMPT/$MAX_RETRIES"
    
    # Build agent prompt
    AGENT_PROMPT="You are $AGENT working on $PROJECT.

Step $((i+1)): $STEP_PROMPT

Project path: $PROJECT"

    if [ -n "$LAST_ERROR" ]; then
      AGENT_PROMPT="$AGENT_PROMPT

⚠️ PREVIOUS ATTEMPT FAILED:
$LAST_ERROR

Fix this error. Do NOT repeat the same mistake."
    fi

    AGENT_PROMPT="$AGENT_PROMPT

When done, commit: cd $PROJECT && git add -A && git commit -m '#$THREAD step $((i+1)): $STEP_PROMPT'
Then create marker: mkdir -p /tmp/engine-steps && echo 'done' > /tmp/engine-steps/${AGENT}-${THREAD}-step${i}.done"

    # Write prompt file for orchestrator
    PROMPT_FILE="/tmp/engine-steps/${AGENT}-${THREAD}-step${i}-attempt${ATTEMPT}.prompt"
    mkdir -p /tmp/engine-steps
    echo "$AGENT_PROMPT" > "$PROMPT_FILE"
    echo "📝 Prompt: $PROMPT_FILE"
    
    # Signal to orchestrator that a step needs running
    echo "{\"agent\":\"$AGENT\",\"thread\":\"$THREAD\",\"step\":$i,\"attempt\":$ATTEMPT,\"prompt_file\":\"$PROMPT_FILE\",\"check\":\"$STEP_CHECK\"}" > "/tmp/engine-steps/${AGENT}-${THREAD}-step${i}-pending.json"
    
    echo "⏳ Waiting for agent to complete step..."
    
    # Wait for done marker (max 5 min per step)
    WAITED=0
    while [ $WAITED -lt 300 ]; do
      if [ -f "/tmp/engine-steps/${AGENT}-${THREAD}-step${i}.done" ]; then
        break
      fi
      sleep 5
      WAITED=$((WAITED + 5))
    done
    
    if [ ! -f "/tmp/engine-steps/${AGENT}-${THREAD}-step${i}.done" ]; then
      LAST_ERROR="Agent timed out (5 min). Step not completed."
      echo "⏰ Timeout"
      continue
    fi
    
    rm -f "/tmp/engine-steps/${AGENT}-${THREAD}-step${i}.done"
    
    # Run verification
    if [ -n "$STEP_CHECK" ]; then
      echo "🔍 Verifying..."
      CHECK_OUTPUT=$(bash "$ENGINE_DIR/check.sh" $STEP_CHECK 2>&1) && {
        echo "$CHECK_OUTPUT"
        STEP_PASSED=true
      } || {
        LAST_ERROR="$CHECK_OUTPUT"
        echo "❌ Check failed: $CHECK_OUTPUT"
      }
    else
      echo "⚠️ No check defined, assuming pass"
      STEP_PASSED=true
    fi
  done
  
  if [ "$STEP_PASSED" = true ]; then
    PASSED=$((PASSED + 1))
    bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "✅ שלב $((i+1))/$STEP_COUNT הושלם" 2>/dev/null || true
  else
    FAILED=$((FAILED + 1))
    bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "❌ שלב $((i+1))/$STEP_COUNT נכשל אחרי $MAX_RETRIES ניסיונות: $LAST_ERROR" 2>/dev/null || true
  fi
done

# After screenshot
if [ -n "$URL" ]; then
  bash "$ENGINE_DIR/check.sh" screenshot "$URL" "/tmp/engine-after-${AGENT}-${THREAD}.png" 2>/dev/null || true
fi

# Summary
echo ""
echo "═══════════════════════════════════════"
echo "📊 Results: $PASSED passed, $FAILED failed out of $STEP_COUNT steps"
echo "═══════════════════════════════════════"

# Report to General
SUMMARY="📊 ${AGENT}-${THREAD}: $PASSED/$STEP_COUNT שלבים עברו"
[ $FAILED -gt 0 ] && SUMMARY="$SUMMARY ($FAILED נכשלו)"
bash "$SWARM_DIR/send.sh" or 1 "$SUMMARY" 2>/dev/null || true

# Save result
cat > "/tmp/engine-results/${AGENT}-${THREAD}.json" << EOF
{"agent":"$AGENT","thread":"$THREAD","passed":$PASSED,"failed":$FAILED,"total":$STEP_COUNT,"before":"/tmp/engine-before-${AGENT}-${THREAD}.png","after":"/tmp/engine-after-${AGENT}-${THREAD}.png"}
EOF

[ $FAILED -eq 0 ] && exit 0 || exit 1
