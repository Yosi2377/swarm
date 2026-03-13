#!/bin/bash
# smart-check.sh — Generate verification checks from task description
# Usage: smart-check.sh "task description" "project_dir" "url"
# Output: one check command per line
set -euo pipefail

TASK="${1:?Usage: smart-check.sh 'task' [project] [url]}"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"

# Always: HTTP and git
echo "http_status $URL 200"
echo "git_changed $PROJECT 1"

TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

# Rename/replace: detect old→new names
if echo "$TASK" | grep -qE 'שנה.*מ-|שנה.*שם|rename|rebrand|replace.*with'; then
  # Hebrew pattern: מ-OLD ל-NEW
  OLD=$(echo "$TASK" | grep -oP '(?:מ-|from\s+)["\x27]?\K[A-Za-z0-9_-]+' | head -1)
  NEW=$(echo "$TASK" | grep -oP '(?:ל-|to\s+)["\x27]?\K[A-Za-z0-9_-]+' | head -1)
  [ -n "$OLD" ] && echo "grep_content_absent $URL $OLD"
  [ -n "$NEW" ] && echo "grep_content $URL $NEW"
fi

# Translation/Hebrew
if echo "$TASK_LOWER" | grep -qE 'תרגום|תרגם|translat|עברית|hebrew'; then
  echo "grep_content $URL [א-ת]"
fi

# CSS/design
if echo "$TASK_LOWER" | grep -qE 'עיצוב|design|css|color|צבע|style|לוגו|logo'; then
  echo "file_exists /tmp/agent-*-final.png"
fi

# Fix/bug
if echo "$TASK_LOWER" | grep -qE 'תקן|fix|bug|שגיאה|error|crash'; then
  echo "no_console_errors $URL"
fi

# Add/create content
if echo "$TASK_LOWER" | grep -qE 'הוסף|add|create|צור|new'; then
  ELEMENT=$(echo "$TASK" | grep -oP '(?:הוסף|add|create|צור)\s+\K\S+' | head -1)
  [ -n "$ELEMENT" ] && echo "grep_content $URL $ELEMENT"
fi
