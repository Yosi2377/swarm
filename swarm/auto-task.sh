#!/bin/bash
# auto-task.sh — Auto-detect target file and lessons for a task
# Usage: auto-task.sh TASK_ID AGENT "description"
TASK_ID="$1"
AGENT="$2"
DESC="$3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$TASK_ID" ] || [ -z "$AGENT" ] || [ -z "$DESC" ]; then
  echo "Usage: auto-task.sh TASK_ID AGENT 'description'"
  exit 1
fi

# Query lessons
echo "📚 Querying lessons..."
LESSONS=$(bash "$SCRIPT_DIR/learn.sh" query "$DESC" 2>&1 | head -5)
echo "$LESSONS"

# Detect target file
TARGET=""
if echo "$DESC" | grep -qi "index\|frontend\|UI\|button\|css\|footer\|header\|banner\|login"; then
  TARGET="/root/sandbox/BettingPlatform/backend/public/index.html"
elif echo "$DESC" | grep -qi "admin\|dashboard\|panel"; then
  TARGET="/root/sandbox/BettingPlatform/backend/public/admin.html"
elif echo "$DESC" | grep -qi "agent\|player\|registration"; then
  TARGET="/root/sandbox/BettingPlatform/backend/public/agent.html"
elif echo "$DESC" | grep -qi "aggregator\|odds\|sync\|parser"; then
  TARGET="/root/sandbox/BettingPlatform/aggregator/aggregator.js"
elif echo "$DESC" | grep -qi "backend\|server\|route\|api\|mongo"; then
  TARGET="/root/sandbox/BettingPlatform/backend/server.js"
else
  TARGET="/root/sandbox/BettingPlatform/backend/public/index.html"
fi

echo ""
echo "🎯 Target: $TARGET"
echo "📋 Task: $DESC"
echo "🔧 Agent: $AGENT"
echo ""
echo "Instructions for agent:"
echo "  1. Edit $TARGET"
echo "  2. bash $SCRIPT_DIR/pipeline.sh $TASK_ID $AGENT $TARGET \"$DESC\""
echo ""
echo "$LESSONS"
