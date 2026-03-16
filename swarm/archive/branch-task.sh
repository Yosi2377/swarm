#!/bin/bash
# branch-task.sh — Create or switch to a task branch
# Usage: branch-task.sh TASK_ID AGENT

set -e
TASK_ID="$1"
AGENT="$2"

if [ -z "$TASK_ID" ] || [ -z "$AGENT" ]; then
  echo "Usage: branch-task.sh TASK_ID AGENT"
  exit 1
fi

cd /root/.openclaw/workspace

BRANCH="task-${TASK_ID}-${AGENT}"

# Fetch latest
git fetch origin master 2>/dev/null || true

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "🔄 Branch '$BRANCH' exists — switching to it"
  git checkout "$BRANCH"
else
  echo "🌿 Creating branch '$BRANCH' from master"
  git checkout master
  git pull origin master 2>/dev/null || true
  git checkout -b "$BRANCH"
fi

echo "✅ On branch: $(git branch --show-current)"
