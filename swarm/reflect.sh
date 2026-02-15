#!/bin/bash
# reflect.sh <agent_id> <thread_id>
# Runs reflection checks: past lessons, git diff, sandbox health, outputs report

set -euo pipefail

AGENT="${1:?Usage: reflect.sh <agent_id> <thread_id>}"
THREAD="${2:?Usage: reflect.sh <agent_id> <thread_id>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="$DIR/memory"
REPORT="$MEMORY_DIR/task-${THREAD}.md"

mkdir -p "$MEMORY_DIR"

{
  echo "# 🪞 Reflection Report — Agent: $AGENT | Thread: $THREAD"
  echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # 1. Query relevant lessons
  echo "## 📚 Past Lessons"
  if [ -f "$DIR/learn.sh" ]; then
    bash "$DIR/learn.sh" query "$AGENT" 2>/dev/null || echo "_No lessons found._"
  else
    echo "_learn.sh not found._"
  fi
  echo ""

  # 2. Git diff in sandbox
  echo "## 📊 Git Diff (Sandbox)"
  SANDBOX="/root/sandbox"
  if [ -d "$SANDBOX" ]; then
    # Find first project dir with .git
    for proj in "$SANDBOX"/*/; do
      if [ -d "$proj/.git" ]; then
        echo "**Project:** $(basename "$proj")"
        (cd "$proj" && git diff --stat 2>/dev/null || echo "_No changes._")
        echo ""
      fi
    done
  else
    echo "_No sandbox found._"
  fi
  echo ""

  # 3. Sandbox URL health check
  echo "## 🌐 Sandbox URL Check"
  # Try common sandbox ports
  SANDBOX_OK=false
  for PORT in 9089 3000 8080 5000; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null || echo "000")
    if [ "$STATUS" != "000" ]; then
      echo "- Port $PORT: HTTP $STATUS"
      [ "$STATUS" = "200" ] && SANDBOX_OK=true
    fi
  done
  $SANDBOX_OK || echo "_No sandbox URL responding with 200._"
  echo ""

  # 4. Reflection questions
  echo "## ❓ Reflection Questions (Answer These!)"
  echo "1. מה יכול להישבר בגלל השינוי שלי?"
  echo "2. האם בדקתי את כל ה-edge cases?"
  echo "3. האם המשתמש יראה בדיוק מה שהוא ביקש?"
  echo "4. האם יש side effects על פיצ'רים אחרים?"
  echo "5. אם הייתי המשתמש, מה הייתי מתלונן עליו?"
  echo ""
  echo "---"
  echo "_Fill in answers above before reporting done._"

} > "$REPORT"

echo "✅ Reflection report saved to: $REPORT"
cat "$REPORT"
