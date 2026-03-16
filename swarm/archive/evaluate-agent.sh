#!/bin/bash
# evaluate-agent.sh — Evaluate a completed agent's work
# Usage: evaluate-agent.sh <agent_id> <thread_id> <task_description> <project_dir>
# Called by orchestrator after agent reports "done"
# Returns: PASS or FAIL with details

AGENT_ID="$1"
THREAD_ID="$2"
TASK_DESC="$3"
PROJECT_DIR="${4:-/root/BotVerse}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== EVALUATING: ${AGENT_ID} task ${THREAD_ID} ==="

ISSUES=0

# 1. Check if server is running (if project has one)
for port in 3000 4000 5000 8000 8080 9000; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null)
    if [ "$CODE" = "000" ] || [ "$CODE" = "502" ] || [ "$CODE" = "503" ]; then
      echo "❌ Server on port $port is DOWN (HTTP $CODE)"
      ISSUES=$((ISSUES+1))
    else
      echo "✅ Server on port $port: HTTP $CODE"
    fi
  fi
done

# 2. Run project tests if they exist
if [ -d "$PROJECT_DIR" ]; then
  cd "$PROJECT_DIR"
  if [ -f "tests/e2e.sh" ]; then
    echo "Running E2E tests..."
    RESULT=$(timeout 120 bash tests/e2e.sh 2>&1 | tail -5)
    if echo "$RESULT" | grep -qE "Failed: [1-9]|Error:"; then
      echo "❌ Tests have failures:"
      echo "$RESULT"
      ISSUES=$((ISSUES+1))
    else
      echo "✅ Tests pass"
    fi
  elif [ -f "package.json" ] && grep -q '"test"' package.json; then
    echo "Running npm test..."
    RESULT=$(timeout 120 npm test 2>&1 | tail -5)
    if [ $? -ne 0 ]; then
      echo "❌ npm test failed"
      ISSUES=$((ISSUES+1))
    else
      echo "✅ npm test pass"
    fi
  fi
  
  # 3. Check git - are there uncommitted changes?
  if [ -d ".git" ]; then
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$DIRTY" -gt 0 ]; then
      echo "⚠️ $DIRTY uncommitted changes"
    fi
  fi
fi

# 4. Summary
echo ""
if [ "$ISSUES" -eq 0 ]; then
  echo "✅ EVALUATION: PASS"
  echo "PASS"
else
  echo "❌ EVALUATION: FAIL ($ISSUES issues)"
  echo "FAIL"
fi
