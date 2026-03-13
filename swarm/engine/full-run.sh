#!/bin/bash
# full-run.sh — COMPLETE end-to-end engine: orchestrate → spawn → verify → retry → report
# This is the ONE script that does everything. No manual intervention.
# Usage: full-run.sh "task description" [project_dir] [url]
set -euo pipefail

TASK="$1"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"
ENGINE_DIR="$(dirname "$0")"
SWARM_DIR="$(dirname "$ENGINE_DIR")"
MAX_RETRIES=3
STEP_TIMEOUT=300  # 5 minutes per attempt

# 1. ORCHESTRATE — classify, create topic, build prompt
echo "📋 Orchestrating: $TASK"
ORCH_OUTPUT=$(bash "$ENGINE_DIR/orchestrate.sh" "$TASK" "$PROJECT" "$URL" 2>/dev/null)
AGENT=$(echo "$ORCH_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['agent'])")
THREAD=$(echo "$ORCH_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['thread'])")
PROMPT_FILE=$(echo "$ORCH_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['prompt_file'])")
CHECK_CMD=$(echo "$ORCH_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['check'])")

echo "🤖 Agent: $AGENT | Thread: $THREAD"

# 2. RETRY LOOP
ATTEMPT=0
PASSED=false
LAST_ERROR=""

while [ $ATTEMPT -lt $MAX_RETRIES ] && [ "$PASSED" = false ]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo ""
  echo "═══ Attempt $ATTEMPT/$MAX_RETRIES ═══"
  
  # Clean done marker
  rm -f "/tmp/engine-steps/${AGENT}-${THREAD}.done"
  
  # Read current prompt
  PROMPT=$(cat "$PROMPT_FILE")
  
  # If retry — enrich prompt with error
  if [ -n "$LAST_ERROR" ]; then
    ENRICHED_PROMPT="$PROMPT

⚠️ PREVIOUS ATTEMPT FAILED:
$LAST_ERROR
Fix this. Do NOT repeat the same mistake."
    PROMPT_FILE="/tmp/engine-tasks/${AGENT}-${THREAD}-attempt${ATTEMPT}.prompt"
    echo "$ENRICHED_PROMPT" > "$PROMPT_FILE"
    echo "📝 Enriched prompt with error"
  fi
  
  # Signal for external spawner (write spawn request)
  cat > "/tmp/engine-tasks/${AGENT}-${THREAD}-spawn.json" << EOF
{"agent":"$AGENT","thread":"$THREAD","attempt":$ATTEMPT,"prompt_file":"$PROMPT_FILE","label":"${AGENT}-${THREAD}"}
EOF
  echo "🚀 Spawn request: /tmp/engine-tasks/${AGENT}-${THREAD}-spawn.json"
  echo "⏳ Waiting for done marker (max ${STEP_TIMEOUT}s)..."
  
  # Wait for done marker
  WAITED=0
  while [ $WAITED -lt $STEP_TIMEOUT ]; do
    if [ -f "/tmp/engine-steps/${AGENT}-${THREAD}.done" ]; then
      echo "📦 Agent reported done after ${WAITED}s"
      break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
  done
  
  if [ ! -f "/tmp/engine-steps/${AGENT}-${THREAD}.done" ]; then
    LAST_ERROR="Agent timed out after ${STEP_TIMEOUT}s"
    echo "⏰ Timeout"
    bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "⏰ Timeout attempt $ATTEMPT" 2>/dev/null || true
    continue
  fi
  
  # 3. VERIFY — engine checks independently
  echo "🔍 Verifying..."
  CHECK_OUTPUT=$(bash "$ENGINE_DIR/check.sh" $CHECK_CMD 2>&1) && {
    echo "$CHECK_OUTPUT"
    
    # Additional checks
    EXTRA_PASS=true
    # Check screenshot exists
    if [ -f "/tmp/agent-${AGENT}-final.png" ]; then
      echo "✅ Agent screenshot exists"
    else
      echo "⚠️ No agent screenshot (non-critical)"
    fi
    
    # Check git commit
    cd "$PROJECT" 2>/dev/null && {
      LAST_COMMIT=$(git log --oneline -1 2>/dev/null)
      echo "📝 Last commit: $LAST_COMMIT"
    }
    
    PASSED=true
  } || {
    LAST_ERROR="$CHECK_OUTPUT"
    echo "❌ Verification failed: $CHECK_OUTPUT"
    bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "❌ Verify failed (attempt $ATTEMPT): $CHECK_OUTPUT" 2>/dev/null || true
  }
done

# 4. LEARN — save the lesson
if [ "$PASSED" = true ]; then
  bash "$ENGINE_DIR/learn.sh" save "$AGENT" "$TASK" pass "Completed in $ATTEMPT attempt(s)" 2>/dev/null || true
else
  bash "$ENGINE_DIR/learn.sh" save "$AGENT" "$TASK" fail "Failed after $MAX_RETRIES attempts: $LAST_ERROR" 2>/dev/null || true
fi

# 5. REPORT
if [ "$PASSED" = true ]; then
  # After screenshot
  bash "$ENGINE_DIR/check.sh" screenshot "$URL" "/tmp/engine-after-${AGENT}-${THREAD}.png" 2>/dev/null || true
  
  echo ""
  echo "═══════════════════════════"
  echo "✅ PASS — $AGENT-$THREAD ($ATTEMPT attempt(s))"
  echo "═══════════════════════════"
  
  # Report to General
  bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "✅ הושלם ($ATTEMPT ניסיונות)" 2>/dev/null || true
  bash "$SWARM_DIR/send.sh" or 1 "✅ ${AGENT}-${THREAD} הושלם: ${TASK:0:60}" 2>/dev/null || true
  
  # Output paths for caller
  echo "AFTER_SCREENSHOT=/tmp/engine-after-${AGENT}-${THREAD}.png"
  echo "AGENT_SCREENSHOT=/tmp/agent-${AGENT}-final.png"
  exit 0
else
  # 6. ESCALATE
  echo ""
  echo "═══════════════════════════"
  echo "❌ FAIL — $AGENT-$THREAD after $MAX_RETRIES attempts"
  echo "═══════════════════════════"
  
  bash "$ENGINE_DIR/escalate.sh" "$AGENT" "$THREAD" "$TASK" "$LAST_ERROR" 2>/dev/null || true
  bash "$SWARM_DIR/send.sh" or 1 "❌ ${AGENT}-${THREAD} נכשל: ${TASK:0:60}" 2>/dev/null || true
  exit 1
fi
