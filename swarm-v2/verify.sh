#!/bin/bash
# verify.sh — Check if agent actually completed the work
# Usage: verify.sh <agent_id> <thread_id>
# Returns: 0=PASS, 1=FAIL
set -euo pipefail

AGENT="$1"
THREAD="$2"
SWARM_V1="/root/.openclaw/workspace/swarm"
DONE_FILE="/tmp/agent-done/${AGENT}-${THREAD}.json"
SCREENSHOT="/tmp/agent-${AGENT}-${THREAD}.png"
RESULTS=""
PASS=true

check() {
  local name="$1" result="$2"
  if [ "$result" = "true" ]; then
    RESULTS="${RESULTS}✅ $name\n"
  else
    RESULTS="${RESULTS}❌ $name\n"
    PASS=false
  fi
}

# 1. Done marker exists?
[ -f "$DONE_FILE" ] && check "Done marker" "true" || check "Done marker" "false"

# 2. Screenshot exists?
[ -f "$SCREENSHOT" ] && check "Screenshot" "true" || check "Screenshot" "false"

# 3. Done marker has status=done?
if [ -f "$DONE_FILE" ]; then
  STATUS=$(python3 -c "import json; print(json.load(open('$DONE_FILE')).get('status',''))" 2>/dev/null || echo "")
  [ "$STATUS" = "done" ] && check "Status=done" "true" || check "Status=done ($STATUS)" "false"
fi

# 4. Summary
echo -e "\n=== Verify: ${AGENT}-${THREAD} ==="
echo -e "$RESULTS"

# 5. Send screenshot to Telegram if exists
if [ -f "$SCREENSHOT" ]; then
  echo "📸 Screenshot found, sending to topic $THREAD and General..."
  # Screenshot sending is handled by the orchestrator via message tool
  echo "SCREENSHOT_PATH=$SCREENSHOT"
fi

if [ "$PASS" = true ]; then
  echo "🟢 PASS"
  bash "$SWARM_V1/send.sh" "$AGENT" "$THREAD" "✅ Verify PASS" 2>/dev/null || true
  exit 0
else
  echo "🔴 FAIL"
  bash "$SWARM_V1/send.sh" "$AGENT" "$THREAD" "❌ Verify FAIL" 2>/dev/null || true
  exit 1
fi
