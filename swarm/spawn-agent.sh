#!/bin/bash
# spawn-agent.sh — Create a new specialized agent on-the-fly
# Usage: spawn-agent.sh AGENT_NAME EMOJI ROLE DESCRIPTION
AGENT_NAME="$1"
EMOJI="$2"
ROLE="$3"
DESC="$4"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$AGENT_NAME" ] || [ -z "$EMOJI" ] || [ -z "$ROLE" ] || [ -z "$DESC" ]; then
  echo "Usage: spawn-agent.sh NAME EMOJI ROLE DESCRIPTION"
  echo "Example: spawn-agent.sh optimizer ⚡ 'performance' 'Optimize page load speed'"
  exit 1
fi

echo "🤖 Creating agent: $AGENT_NAME ($EMOJI)"

# 1. Create agent skill file
SKILL_DIR="$SCRIPT_DIR/agents/$AGENT_NAME"
mkdir -p "$SKILL_DIR"
cat > "$SKILL_DIR/AGENT.md" << EOF
# Agent: $AGENT_NAME ($EMOJI)
**Role**: $ROLE
**Description**: $DESC
**Created**: $(date -Iseconds)

## Capabilities
- Read and modify project files
- Run pipeline.sh for tested deployments
- Use learn.sh to record lessons
- Use send.sh to communicate

## Instructions
When activated, this agent should:
1. Understand the task related to: $ROLE
2. Find relevant files using auto-task.sh
3. Make changes
4. Run pipeline.sh
5. Report results

## History
(auto-populated by learn.sh)
EOF

# 2. Add to SYSTEM.md agent table
if ! grep -q "$AGENT_NAME" "$SCRIPT_DIR/SYSTEM.md" 2>/dev/null; then
  echo "| $AGENT_NAME | $EMOJI | $ROLE | @Team${AGENT_NAME^}_Bot |" >> "$SCRIPT_DIR/SYSTEM.md" 2>/dev/null || true
fi

# 3. Create agent-specific lessons file
cat > "$SKILL_DIR/lessons.json" << EOF
{"agent": "$AGENT_NAME", "lessons": [], "created": "$(date -Iseconds)"}
EOF

echo "✅ Agent '$AGENT_NAME' created!"
echo "📂 Skill dir: $SKILL_DIR"
echo "📋 AGENT.md: $SKILL_DIR/AGENT.md"
echo ""
echo "To activate:"
echo "  sessions_spawn with task: 'אתה $AGENT_NAME ($EMOJI). קרא $SKILL_DIR/AGENT.md. [TASK]'"
