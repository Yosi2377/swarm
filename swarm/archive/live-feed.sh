#!/bin/bash
# live-feed.sh — Posts real-time progress updates to Agent Chat (topic 479)
# Usage: live-feed.sh <agent_id> <thread_id> <step> <message>
#
# Steps:
#   start    — Agent started working
#   progress — Agent working (with details)
#   test     — Running tests
#   fail     — Test failed, retrying
#   retry    — Agent retrying after feedback
#   eval     — Evaluator checking
#   pass     — All tests passed
#   done     — Sent to user for approval
#   deploy   — Deployed to production
#   error    — Something went wrong

set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="${1:?Usage: live-feed.sh <agent_id> <thread_id> <step> <message>}"
THREAD="${2:?}"
STEP="${3:?}"
MSG="${4:-}"
AGENT_CHAT=479
BOT_TOKEN=$(cat "$SWARM_DIR/.bot-token" 2>/dev/null)

# Agent emoji lookup
get_emoji() {
  case "$1" in
    or) echo "✨" ;;
    koder) echo "⚙️" ;;
    shomer) echo "🔒" ;;
    tzayar) echo "🎨" ;;
    worker) echo "🤖" ;;
    researcher) echo "🔍" ;;
    *) echo "🔄" ;;
  esac
}

EMOJI=$(get_emoji "$AGENT")
TIME=$(date '+%H:%M:%S')

# Step-specific formatting
case "$STEP" in
  start)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
📋 התחיל לעבוד: $MSG"
    ;;
  progress)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
⏳ $MSG"
    ;;
  code)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
💻 שינוי קוד: $MSG"
    ;;
  test)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
🧪 מריץ בדיקות..."
    ;;
  fail)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
❌ בדיקה נכשלה: $MSG"
    ;;
  retry)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
🔄 מנסה שוב (ניסיון $MSG)"
    ;;
  eval)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
🔍 evaluator בודק..."
    ;;
  pass)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
✅ כל הבדיקות עברו!"
    ;;
  done)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
📸 נשלח ליוסי לאישור"
    ;;
  deploy)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
🚀 הועבר לפרודקשן!"
    ;;
  error)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
🚨 שגיאה: $MSG"
    ;;
  feedback)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
💬 feedback: $MSG"
    ;;
  *)
    TEXT="$TIME | $EMOJI $AGENT → #$THREAD
$STEP: $MSG"
    ;;
esac

# Send to Agent Chat (479)
"$SWARM_DIR/send.sh" "$AGENT" "$AGENT_CHAT" "$TEXT" > /dev/null 2>&1

# Also log to file
echo "$TEXT" >> "$SWARM_DIR/logs/live-feed.log" 2>/dev/null
