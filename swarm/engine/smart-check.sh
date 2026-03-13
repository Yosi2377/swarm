#!/bin/bash
# smart-check.sh — Generates appropriate checks based on task type
# Usage: smart-check.sh "task description" "project_dir" "url"
# Output: check commands (one per line) that the engine should run
set -euo pipefail

TASK="$1"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"
ENGINE_DIR="$(dirname "$0")"

CHECKS=()

# Always: HTTP must work
CHECKS+=("http_status $URL 200")

# Always: must have git changes
CHECKS+=("git_changed $PROJECT 1")

# Always: screenshot for visual verify
CHECKS+=("screenshot $URL /tmp/engine-verify-latest.png")

# CONTENT CHECKS — based on task keywords
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

# Rename/rebrand tasks: old name must be GONE
if echo "$TASK_LOWER" | grep -qE "שנה.*שם|rename|rebrand|replace.*with"; then
  # Extract old→new from task (look for → or "to" or ל)
  OLD=$(echo "$TASK" | grep -oP '(?:מ|from\s+)["\x27]?\K[A-Za-z]+' | head -1)
  NEW=$(echo "$TASK" | grep -oP '(?:ל|to\s+)["\x27]?\K[A-Za-z]+' | head -1)
  if [ -n "$OLD" ]; then
    CHECKS+=("grep_content_absent $URL $OLD")
  fi
  if [ -n "$NEW" ]; then
    CHECKS+=("grep_content $URL $NEW")
  fi
fi

# Translation tasks: target language must appear
if echo "$TASK_LOWER" | grep -qE "תרגום|translat|עברית|hebrew"; then
  CHECKS+=("grep_content $URL [א-ת]")
fi

# Add/create tasks: new element must exist
if echo "$TASK_LOWER" | grep -qE "הוסף|add|create|צור"; then
  # Try to find what should be added
  ELEMENT=$(echo "$TASK" | grep -oP '(?:הוסף|add|create)\s+\K\S+' | head -1)
  if [ -n "$ELEMENT" ]; then
    CHECKS+=("grep_content $URL $ELEMENT")
  fi
fi

# CSS/design tasks: check for visual changes via screenshot diff
if echo "$TASK_LOWER" | grep -qE "עיצוב|design|css|color|צבע|style"; then
  CHECKS+=("file_exists /tmp/agent-*-final.png")
fi

# Fix/bug tasks: the error should be gone
if echo "$TASK_LOWER" | grep -qE "תקן|fix|bug|שגיאה|error"; then
  CHECKS+=("no_console_errors $URL")
fi

# Output all checks
for check in "${CHECKS[@]}"; do
  echo "$check"
done
