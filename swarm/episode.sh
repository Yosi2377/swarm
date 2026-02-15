#!/bin/bash
# episode.sh — Episodic Memory: save completed tasks as "episodes" for future reference
# Usage:
#   episode.sh save <task_id>            — Save task as episode
#   episode.sh find <keyword>            — Find similar episodes
#   episode.sh list                      — List all episodes
set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
EPISODES_DIR="$SWARM_DIR/learning/episodes"
TASKS_FILE="$SWARM_DIR/tasks.json"
TASKS_DIR="$SWARM_DIR/tasks"

mkdir -p "$EPISODES_DIR"

case "${1:-help}" in

save)
  TASK_ID="$2"
  if [ -z "$TASK_ID" ]; then
    echo "Usage: episode.sh save <task_id>"
    exit 1
  fi
  
  # Get task from completed or active
  TASK=$(jq --argjson id "$TASK_ID" '(.completed[] // .tasks[]) | select(.id == $id)' "$TASKS_FILE" 2>/dev/null || echo "")
  if [ -z "$TASK" ]; then
    echo "Task #$TASK_ID not found"
    exit 1
  fi
  
  AGENT=$(echo "$TASK" | jq -r '.agent')
  THREAD=$(echo "$TASK" | jq -r '.thread')
  TITLE=$(echo "$TASK" | jq -r '.title')
  SUMMARY=$(echo "$TASK" | jq -r '.summary // "no summary"')
  STARTED=$(echo "$TASK" | jq -r '.startedAt // "unknown"')
  COMPLETED=$(echo "$TASK" | jq -r '.completedAt // "unknown"')
  
  # Get task file content if exists
  TASK_CONTENT=""
  if [ -f "$TASKS_DIR/$THREAD.md" ]; then
    TASK_CONTENT=$(cat "$TASKS_DIR/$THREAD.md")
  fi
  
  # Get relevant lessons
  LESSONS=$(python3 -c "
import json
with open('$SWARM_DIR/learning/lessons.json') as f: data = json.load(f)
agent_lessons = [l for l in data['lessons'] if l['agent'] == '$AGENT']
for l in agent_lessons[-5:]:
    print(f\"- [{l['severity']}] {l['lesson']}\")
" 2>/dev/null || echo "No lessons")
  
  # Save episode
  EPISODE_FILE="$EPISODES_DIR/episode-${TASK_ID}.md"
  cat > "$EPISODE_FILE" << EOF
# Episode #$TASK_ID: $TITLE

## Metadata
- **Agent**: $AGENT
- **Thread**: $THREAD
- **Started**: $STARTED
- **Completed**: $COMPLETED
- **Summary**: $SUMMARY

## Task Description
$TASK_CONTENT

## Lessons from this Task
$LESSONS

## Tags
<!-- Add searchable tags here -->
$AGENT, $(echo "$TITLE" | tr ' ' '\n' | grep -E '.{4,}' | tr '\n' ', ' || echo "")
EOF
  
  echo "💾 Episode saved: $EPISODE_FILE"
  ;;

find)
  KEYWORD="${2:-}"
  if [ -z "$KEYWORD" ]; then
    echo "Usage: episode.sh find <keyword>"
    exit 1
  fi
  
  echo "🔍 Searching episodes for: $KEYWORD"
  echo "=================================="
  
  FOUND=0
  for ep in "$EPISODES_DIR"/episode-*.md; do
    [ -f "$ep" ] || continue
    if grep -il "$KEYWORD" "$ep" >/dev/null 2>&1; then
      TITLE=$(head -1 "$ep" | sed 's/^# //')
      AGENT=$(grep "Agent" "$ep" | head -1 | sed 's/.*: //')
      echo "  📖 $TITLE (by $AGENT)"
      echo "     $(basename "$ep")"
      FOUND=$((FOUND + 1))
    fi
  done
  
  if [ "$FOUND" -eq 0 ]; then
    echo "  No episodes found for: $KEYWORD"
  else
    echo "=================================="
    echo "Found $FOUND episode(s)"
  fi
  ;;

list)
  echo "📚 All Episodes"
  echo "=================================="
  for ep in "$EPISODES_DIR"/episode-*.md; do
    [ -f "$ep" ] || { echo "  No episodes yet."; break; }
    TITLE=$(head -1 "$ep" | sed 's/^# //')
    AGENT=$(grep "Agent" "$ep" | head -1 | sed 's/.*: //' 2>/dev/null || echo "?")
    echo "  📖 $TITLE ($AGENT)"
  done
  ;;

*)
  echo "📚 Episodic Memory"
  echo "Usage:"
  echo "  episode.sh save <task_id>     — Save completed task as episode"
  echo "  episode.sh find <keyword>     — Find similar past episodes"
  echo "  episode.sh list               — List all episodes"
  ;;
esac
