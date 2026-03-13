#!/bin/bash
# agent-runner.sh — Run agent, monitor, verify, report
# Usage: agent-runner.sh <agent_id> <thread_id> "task" [project_dir] [--dry-run]
set -euo pipefail

AGENT="$1"
THREAD="$2"
TASK="$3"
PROJECT_DIR="${4:-/root/.openclaw/workspace}"
DRY_RUN="${5:-}"
SWARM_V1="/root/.openclaw/workspace/swarm"
SWARM_V2="$(dirname "$0")"

# Build prompt from template
build_prompt() {
  local url="http://localhost:3200"
  local short_desc="${TASK:0:60}"
  
  sed -e "s|{AGENT}|$AGENT|g" \
      -e "s|{THREAD}|$THREAD|g" \
      -e "s|{TASK}|$TASK|g" \
      -e "s|{PROJECT_DIR}|$PROJECT_DIR|g" \
      -e "s|{URL}|$url|g" \
      -e "s|{SHORT_DESC}|$short_desc|g" \
      "$SWARM_V2/prompt-template.md"
}

PROMPT=$(build_prompt)

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "=== DRY RUN ==="
  echo "$PROMPT"
  echo "=== Would spawn agent $AGENT on thread $THREAD ==="
  exit 0
fi

# Notify topic
bash "$SWARM_V1/send.sh" "$AGENT" "$THREAD" "🔄 מתחיל עבודה על: $TASK" 2>/dev/null || true

# Write prompt to file for the orchestrator to use with sessions_spawn
mkdir -p /tmp/agent-tasks
echo "$PROMPT" > "/tmp/agent-tasks/${AGENT}-${THREAD}.prompt"
echo "📝 Prompt saved to /tmp/agent-tasks/${AGENT}-${THREAD}.prompt"
echo "🚀 Ready for sessions_spawn with label: ${AGENT}-${THREAD}"

# The actual sessions_spawn must be called from the orchestrator (Node/OpenClaw)
# This script prepares everything and the orchestrator reads the prompt file
