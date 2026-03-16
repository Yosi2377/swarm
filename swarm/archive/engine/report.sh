#!/bin/bash
# report.sh — Report task results to Telegram + save lesson
# Usage: report.sh <agent_id> <thread_id> <status> <summary> [screenshot_path]
set -uo pipefail

AGENT="${1:?Usage: report.sh <agent_id> <thread_id> <status> <summary> [screenshot]}"
THREAD="${2:?thread_id required}"
STATUS="${3:?status required (pass|fail|timeout)}"
SUMMARY="${4:-No summary}"
SCREENSHOT="${5:-}"

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
SWARM_DIR="$(dirname "$ENGINE_DIR")"

# Status emoji
case "$STATUS" in
  pass)    EMOJI="✅"; RESULT="pass" ;;
  fail)    EMOJI="❌"; RESULT="fail" ;;
  timeout) EMOJI="⏰"; RESULT="fail" ;;
  *)       EMOJI="ℹ️"; RESULT="$STATUS" ;;
esac

MSG="$EMOJI ${AGENT}-${THREAD}: $SUMMARY"

# Send to agent's topic
if [ -n "$SCREENSHOT" ] && [ -f "$SCREENSHOT" ]; then
  bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "$MSG" --photo "$SCREENSHOT" 2>/dev/null || true
else
  bash "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "$MSG" 2>/dev/null || true
fi

# Send summary to General (topic 1)
bash "$SWARM_DIR/send.sh" "$AGENT" "1" "$MSG" 2>/dev/null || true

# Save lesson
LESSON_TEXT="$STATUS: $SUMMARY"
bash "$ENGINE_DIR/learn.sh" save "$AGENT" "${AGENT}-${THREAD}" "$RESULT" "$LESSON_TEXT" 2>/dev/null || true

echo "Reported: $MSG"
