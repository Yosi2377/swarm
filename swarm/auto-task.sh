#!/bin/bash
# auto-task.sh — Full autonomy: describe what you want, agent figures out the rest
# Usage: auto-task.sh TASK_ID AGENT "high-level description"

TASK_ID="$1"
AGENT="$2"
DESC="$3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$TASK_ID" ] || [ -z "$AGENT" ] || [ -z "$DESC" ]; then
  echo "Usage: auto-task.sh TASK_ID AGENT 'description'"
  exit 1
fi

# 1. Query relevant lessons
echo "📚 Querying lessons..."
LESSONS=$(bash "$SCRIPT_DIR/learn.sh" query "$DESC" 2>&1 | head -5)
echo "$LESSONS"

# 2. Detect target file from description
TARGET=""
if echo "$DESC" | grep -qi "index\|frontend\|UI\|button\|css\|footer\|header\|banner"; then
  TARGET="/root/sandbox/BettingPlatform/backend/public/index.html"
elif echo "$DESC" | grep -qi "admin\|dashboard\|panel"; then
  TARGET="/root/sandbox/BettingPlatform/backend/public/admin.html"
elif echo "$DESC" | grep -qi "agent\|player\|registration"; then
  TARGET="/root/sandbox/BettingPlatform/backend/public/agent.html"
elif echo "$DESC" | grep -qi "aggregator\|odds\|sync\|api\|parser"; then
  TARGET="/root/sandbox/BettingPlatform/aggregator/aggregator.js"
elif echo "$DESC" | grep -qi "backend\|server\|route\|api\|mongo"; then
  TARGET="/root/sandbox/BettingPlatform/backend/server.js"
else
  TARGET="/root/sandbox/BettingPlatform/backend/public/index.html"
fi

echo "🎯 Target file: $TARGET"
echo "📋 Task: $DESC"
echo ""
echo "⚠️ Agent must:"
echo "  1. Edit $TARGET to implement: $DESC"
echo "  2. Run: bash $SCRIPT_DIR/pipeline.sh $TASK_ID $AGENT $TARGET \"$DESC\""
echo ""
echo "📚 Relevant lessons:"
echo "$LESSONS"
