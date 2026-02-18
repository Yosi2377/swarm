#!/bin/bash
# spawn-agent.sh — Create AND activate a new specialized agent
# Usage: spawn-agent.sh AGENT_NAME EMOJI ROLE "TASK_DESCRIPTION"
AGENT_NAME="$1"
EMOJI="$2"
ROLE="$3"
TASK="$4"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$AGENT_NAME" ] || [ -z "$EMOJI" ] || [ -z "$ROLE" ]; then
  echo "Usage: spawn-agent.sh NAME EMOJI ROLE [TASK]"
  echo "Example: spawn-agent.sh optimizer ⚡ performance 'Optimize page load speed'"
  exit 1
fi

# 1. Create agent profile if not exists
SKILL_DIR="$SCRIPT_DIR/agents/$AGENT_NAME"
mkdir -p "$SKILL_DIR"
if [ ! -f "$SKILL_DIR/AGENT.md" ]; then
  cat > "$SKILL_DIR/AGENT.md" << EOF
# Agent: $AGENT_NAME ($EMOJI)
**Role**: $ROLE
**Created**: $(date -Iseconds)

## Instructions
1. Understand tasks related to: $ROLE
2. Find target files: bash swarm/auto-task.sh TASK_ID $AGENT_NAME "description"
3. Edit files on SANDBOX only
4. Run pipeline: bash swarm/pipeline.sh TASK_ID $AGENT_NAME TARGET_FILE "description"

## History
EOF
  echo "✅ Created agent profile: $SKILL_DIR/AGENT.md"
else
  echo "📂 Agent profile exists: $SKILL_DIR/AGENT.md"
fi

# 2. Query relevant lessons
echo "📚 Querying lessons for $ROLE..."
LESSONS=$(bash "$SCRIPT_DIR/learn.sh" query "$ROLE $TASK" 2>&1 | head -5)
echo "$LESSONS"

# 3. If task provided, output the spawn command
if [ -n "$TASK" ]; then
  TASK_ID=$((RANDOM % 9000 + 1000))
  
  echo ""
  echo "🚀 Ready to spawn. Task ID: $TASK_ID"
  echo ""
  echo "Spawn command:"
  echo "  sessions_spawn with:"
  echo "    task: 'אתה $AGENT_NAME ($EMOJI). תפקידך: $ROLE."
  echo "           קרא $SKILL_DIR/AGENT.md."
  echo "           📋 משימה: $TASK"
  echo "           TASK_ID: $TASK_ID"
  echo "           כלים: auto-task.sh, pipeline.sh"
  echo "           תסתדר.'"
  echo "    label: task-${TASK_ID}-${AGENT_NAME}"
  
  # Log spawn
  echo "$(date -Iseconds) | spawn | $AGENT_NAME | $TASK" >> "$SKILL_DIR/history.log"
fi
