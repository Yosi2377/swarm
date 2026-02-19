#!/usr/bin/env bash
#
# setup-ralph-task.sh — Prepare a Ralph Loop workspace for a koder task
#
# Usage: setup-ralph-task.sh <task-id> <project-dir> "<task-title>" "<task-description>"
#
# Creates:
#   <project-dir>/PROMPT.md (planning mode)
#   <project-dir>/AGENTS.md (project context)
#   <project-dir>/specs/task.md (task details)
#   <project-dir>/IMPLEMENTATION_PLAN.md (empty, agent fills)
#   <project-dir>/.ralph/<task-id>/ (logs dir)
#
set -euo pipefail

TASK_ID="${1:?Usage: setup-ralph-task.sh <task-id> <project-dir> <title> <description>}"
PROJECT_DIR="${2:?Missing project-dir}"
TASK_TITLE="${3:?Missing task title}"
TASK_DESC="${4:?Missing task description}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SWARM_DIR/templates"

# Create dirs
mkdir -p "$PROJECT_DIR/specs" "$PROJECT_DIR/.ralph/$TASK_ID"

# PROMPT.md — start in planning mode
sed "s/{{TASK_TITLE}}/$TASK_TITLE/g" "$TEMPLATES_DIR/PROMPT-PLANNING.md" > "$PROJECT_DIR/PROMPT.md"

# specs/task.md — full task description
cat > "$PROJECT_DIR/specs/task.md" << EOF
# $TASK_TITLE

## Task ID: $TASK_ID

## Description
$TASK_DESC

## Created: $(date -Iseconds)
EOF

# IMPLEMENTATION_PLAN.md — empty for agent to fill
cat > "$PROJECT_DIR/IMPLEMENTATION_PLAN.md" << EOF
# Implementation Plan — $TASK_TITLE
# Task: $TASK_ID
# Created: $(date '+%Y-%m-%d %H:%M')

## Tasks
(Agent will fill this during PLANNING phase)

EOF

# AGENTS.md — copy from project or create
if [[ ! -f "$PROJECT_DIR/AGENTS.md" ]]; then
  cat > "$PROJECT_DIR/AGENTS.md" << 'EOF'
# Project Context

## Key Files
(List important files here)

## Test Command
```bash
# test_command: echo "no tests configured"
```

## Verification
# VERIFY_URL: http://localhost:8089

## Constraints
- Use sandbox first, never edit production directly
- chattr -i before editing immutable files, chattr +i after
- Take screenshots before AND after changes
- Actually LOOK at your screenshots before reporting done

## Learnings
(Agent appends lessons learned here)
EOF
fi

# Initialize git if needed
cd "$PROJECT_DIR"
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  git init -q
  git add -A
  git commit -q -m "Initial setup for $TASK_ID" 2>/dev/null || true
fi

echo "✅ Ralph workspace ready: $PROJECT_DIR"
echo "   PROMPT.md  → Planning mode"
echo "   specs/task.md → Task details"
echo ""
echo "Run: ralph-koder.sh $TASK_ID <thread-id> $PROJECT_DIR [max-iters]"
