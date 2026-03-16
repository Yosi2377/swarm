#!/bin/bash
# retry.sh <thread_id> <agent_id> [max_retries]
# Runs evaluator in a loop, sends feedback on failure, escalates after max retries
set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
THREAD="${1:?Usage: retry.sh <thread_id> <agent_id> [max_retries]}"
AGENT="${2:?Missing agent_id}"
MAX_RETRIES="${3:-3}"
CHAT_ID="-1003815143703"

TOKEN=$(cat "$SWARM_DIR/.or-token" 2>/dev/null || cat "$SWARM_DIR/.bot-token" 2>/dev/null)

send_msg() {
  local thread="$1"
  local msg="$2"
  curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$CHAT_ID\",\"message_thread_id\":$thread,\"text\":\"$msg\",\"parse_mode\":\"HTML\"}" >/dev/null 2>&1 || true
}

RETRY_FILE="/tmp/retry-count-${THREAD}.txt"
CURRENT=$(cat "$RETRY_FILE" 2>/dev/null || echo "0")

echo "🔄 Retry loop for thread $THREAD (attempt $((CURRENT+1))/$MAX_RETRIES)"

# Run evaluator
"$SWARM_DIR/evaluator.sh" "$THREAD" "$AGENT" 2>&1
EVAL_RC=$?

if [ $EVAL_RC -eq 0 ]; then
  echo "✅ PASSED on attempt $((CURRENT+1))"
  rm -f "$RETRY_FILE" "/tmp/retry-feedback-${THREAD}.txt"
  [ "$CURRENT" -gt 0 ] && send_msg 1 "✅ Thread $THREAD passed after $((CURRENT+1)) attempts"
  exit 0
fi

# Failed
CURRENT=$((CURRENT + 1))
echo "$CURRENT" > "$RETRY_FILE"

if [ "$CURRENT" -ge "$MAX_RETRIES" ]; then
  echo "🔴 Max retries ($MAX_RETRIES) reached for thread $THREAD"
  send_msg 1 "🔴 <b>ESCALATION</b> — Thread $THREAD failed after $MAX_RETRIES attempts.
Agent: $AGENT
Requires manual intervention."
  send_msg "$THREAD" "🔴 $MAX_RETRIES ניסיונות נכשלו. ממתין להתערבות ידנית."
  rm -f "$RETRY_FILE"
  exit 2
fi

# Send feedback to agent topic for retry
FEEDBACK=$(cat "/tmp/retry-feedback-${THREAD}.txt" 2>/dev/null || echo "Tests failed")
send_msg "$THREAD" "🔄 <b>ניסיון $CURRENT/$MAX_RETRIES נכשל</b>

$FEEDBACK

תקן ודווח שוב. נותרו $((MAX_RETRIES - CURRENT)) ניסיונות."

echo "📝 Feedback sent to thread $THREAD (attempt $CURRENT/$MAX_RETRIES)"
exit 1
