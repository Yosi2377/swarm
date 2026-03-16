#!/bin/bash
# plan.sh — Break a task into verifiable steps
# Usage: plan.sh "task description" "project_dir" "url"
# Output: JSON task file to stdout
set -euo pipefail

TASK="$1"
PROJECT="${2:-/root/pharos-ai}"
URL="${3:-http://localhost:3200}"

# Classify task type and generate steps
# This is deterministic — no LLM needed for basic classification
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

# Auto-detect agent
AGENT="koder"
case "$TASK_LOWER" in
  *עיצוב*|*design*|*css*|*ui*|*ux*) AGENT="tzayar" ;;
  *תרגום*|*translat*|*עברית*|*rtl*) AGENT="front" ;;
  *בדיק*|*test*|*qa*) AGENT="tester" ;;
  *אבטח*|*secur*) AGENT="shomer" ;;
  *דאטא*|*data*|*db*|*mongo*|*sql*) AGENT="data" ;;
  *api*|*backend*|*server*) AGENT="back" ;;
esac

# Generate task JSON with the task as a single step
# The LLM agent will figure out HOW to do it
# We just define WHAT to verify
cat << EOF
{
  "task": "$TASK",
  "project": "$PROJECT",
  "url": "$URL",
  "agent": "$AGENT",
  "steps": [
    {
      "prompt": "$TASK",
      "check": "http_status $URL 200"
    },
    {
      "prompt": "Take a screenshot to prove your work",
      "check": "file_exists /tmp/agent-$AGENT-final.png"
    }
  ]
}
EOF
