#!/bin/bash
# merge-task.sh — Merge a task branch back to master
# Usage: merge-task.sh TASK_ID [AGENT]

set -e
TASK_ID="$1"
AGENT="$2"

if [ -z "$TASK_ID" ]; then
  echo "Usage: merge-task.sh TASK_ID [AGENT]"
  exit 1
fi

cd /root/.openclaw/workspace

# Find the branch (with or without agent suffix)
if [ -n "$AGENT" ]; then
  BRANCH="task-${TASK_ID}-${AGENT}"
else
  # Auto-detect branch matching task-TASKID-*
  BRANCH=$(git branch --list "task-${TASK_ID}-*" | head -1 | tr -d ' *')
  if [ -z "$BRANCH" ]; then
    echo "❌ No branch found for task $TASK_ID"
    exit 1
  fi
fi

if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "❌ Branch '$BRANCH' does not exist"
  exit 1
fi

echo "🔀 Merging '$BRANCH' into master..."

git checkout master
git pull origin master 2>/dev/null || true

# Try merge --no-ff
if git merge --no-ff "$BRANCH" -m "Merge $BRANCH into master"; then
  echo "✅ Merge successful"
  # Delete the branch
  git branch -d "$BRANCH"
  echo "🗑️ Branch '$BRANCH' deleted"
else
  echo "❌ CONFLICT detected! Aborting merge."
  git merge --abort
  echo "⚠️ Branch '$BRANCH' NOT merged. Resolve conflicts manually."
  exit 1
fi
