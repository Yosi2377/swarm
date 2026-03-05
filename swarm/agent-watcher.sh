#!/bin/bash
# agent-watcher.sh — Detects completed agents, evaluates, sends FULL report to Telegram
# No OpenClaw wake needed — this script does EVERYTHING
# Runs every minute via system crontab

DONE_DIR="/tmp/agent-done"
REPORTED_DIR="/tmp/agent-done/reported"
SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DONE_DIR" "$REPORTED_DIR"

OR_TOKEN=$(cat "$SWARM_DIR/.bot-token" 2>/dev/null)
CHAT_ID="-1003815143703"

send_telegram() {
  local topic="$1"
  local msg="$2"
  curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "message_thread_id=${topic}" \
    -d "text=${msg}" \
    -d "parse_mode=HTML" > /dev/null 2>&1
}

for f in "$DONE_DIR"/*.json; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ -f "$REPORTED_DIR/$base" ] && continue
  
  label=$(python3 -c "import json;print(json.load(open('$f')).get('label','unknown'))" 2>/dev/null)
  topic=$(python3 -c "import json;print(json.load(open('$f')).get('topic','4950'))" 2>/dev/null)
  summary=$(python3 -c "import json;print(json.load(open('$f')).get('summary','done'))" 2>/dev/null)
  
  # Step 1: Notify
  send_telegram "$topic" "🤖 סוכן ${label} סיים: ${summary}

⏳ מריץ בדיקות..."

  # Step 2: Evaluate — run tests if project exists
  EVAL_RESULT=""
  for PROJECT_DIR in /root/agent-test-project /root/BotVerse /root/BettingPlatform; do
    if [ -d "$PROJECT_DIR" ]; then
      cd "$PROJECT_DIR"
      
      # Check server
      for port in 3000 4000 4444 5000 8080; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
          CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null)
          EVAL_RESULT="${EVAL_RESULT}Server :${port} → HTTP ${CODE}\n"
        fi
      done
      
      # Run tests
      if [ -f "tests/run.js" ]; then
        TEST_OUT=$(cd "$PROJECT_DIR" && timeout 60 node tests/run.js 2>&1 | tail -8)
        PASSED=$(echo "$TEST_OUT" | grep -oP 'Passed: \K\d+')
        FAILED=$(echo "$TEST_OUT" | grep -oP 'Failed: \K\d+')
        TOTAL=$(echo "$TEST_OUT" | grep -oP 'Total: \K\d+')
        if [ "${FAILED:-0}" = "0" ]; then
          EVAL_RESULT="${EVAL_RESULT}✅ Tests: ${PASSED}/${TOTAL} passed\n"
        else
          EVAL_RESULT="${EVAL_RESULT}❌ Tests: ${PASSED}/${TOTAL} passed, ${FAILED} failed\n"
        fi
      elif [ -f "tests/e2e.sh" ]; then
        TEST_OUT=$(cd "$PROJECT_DIR" && timeout 120 bash tests/e2e.sh 2>&1 | tail -5)
        PASSED=$(echo "$TEST_OUT" | grep -oP 'Passed: \K\d+')
        FAILED=$(echo "$TEST_OUT" | grep -oP 'Failed: \K\d+')
        EVAL_RESULT="${EVAL_RESULT}Tests: ${PASSED:-?} passed, ${FAILED:-?} failed\n"
      fi
      
      # Check git
      if [ -d ".git" ]; then
        DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
        [ "$DIRTY" -gt 0 ] && EVAL_RESULT="${EVAL_RESULT}⚠️ ${DIRTY} uncommitted changes\n"
      fi
    fi
  done
  
  # Step 3: Send full report
  if [ -n "$EVAL_RESULT" ]; then
    VERDICT="✅ PASS"
    echo -e "$EVAL_RESULT" | grep -q "❌" && VERDICT="❌ FAIL"
    
    REPORT="📋 <b>דיווח סוכן: ${label}</b>

${summary}

<b>בדיקות:</b>
$(echo -e "$EVAL_RESULT")
<b>סיכום: ${VERDICT}</b>"
  else
    REPORT="📋 <b>דיווח סוכן: ${label}</b>

${summary}

✅ הושלם (אין בדיקות אוטומטיות)"
  fi
  
  send_telegram "$topic" "$REPORT"
  
  # Also try to wake OpenClaw (best effort)
  HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
  if [ -n "$HOOK_TOKEN" ]; then
    SESSION_KEY="agent:main:telegram:group:${CHAT_ID}:topic:${topic}"
    curl -s -X POST "http://localhost:18789/hooks/agent" \
      -H "Authorization: Bearer ${HOOK_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"message\":\"Agent ${label} completed: ${summary}. Evaluation: ${VERDICT:-done}. Report already sent to Telegram.\",\"sessionKey\":\"${SESSION_KEY}\"}" > /dev/null 2>&1
  fi
  
  # Move to reported
  cp "$f" "$REPORTED_DIR/$base"
  rm "$f"
  
  echo "$(date -Iseconds) Full report: $label → topic $topic"
done
