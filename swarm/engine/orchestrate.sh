#!/bin/bash
# orchestrate.sh — Main entry point for swarm task orchestration
# Usage: orchestrate.sh "task description" [project_dir] [url]
set -uo pipefail

[[ "${1:-}" == "--help" || $# -lt 1 ]] && { echo "Usage: orchestrate.sh \"task description\" [project_dir] [url]"; exit 0; }

TASK="$1"; PROJECT_DIR="${2:-/root/BotVerse}"; URL="${3:-}"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
SWARM_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
TASK_DIR="/tmp/engine-tasks"; mkdir -p "$TASK_DIR" "/tmp/engine-steps"

# 1. Classify task → agent
classify_agent() {
  local t="${1,,}"
  case "$t" in
    *security*|*scan*|*ssl*|*port*|*firewall*) echo "shomer" ;;
    *frontend*|*html*|*css*|*responsive*|*ui*layout*) echo "front" ;;
    *backend*|*api*|*express*|*server*|*route*) echo "back" ;;
    *docker*|*container*|*devops*|*deploy*) echo "docker" ;;
    *database*|*mongo*|*sql*|*migration*|*backup*) echo "data" ;;
    *test*|*qa*|*e2e*) echo "tester" ;;
    *design*|*image*|*logo*|*icon*) echo "tzayar" ;;
    *debug*|*error*|*log*|*profil*) echo "debugger" ;;
    *monitor*|*alert*|*health*|*uptime*) echo "monitor" ;;
    *performance*|*speed*|*cache*|*optimi*) echo "optimizer" ;;
    *refactor*|*cleanup*|*tech.debt*) echo "refactor" ;;
    *research*|*investigate*|*best.practice*) echo "researcher" ;;
    *webhook*|*integration*|*third.party*) echo "integrator" ;;
    *code*|*bug*|*fix*|*implement*|*feature*) echo "koder" ;;
    *) echo "worker" ;;
  esac
}

AGENT=$(classify_agent "$TASK")

# 2. Query lessons
LESSONS=$("$ENGINE_DIR/learn.sh" inject "$AGENT" "$TASK" 2>/dev/null || true)

# 3. Create Telegram topic
TOPIC_NAME="$(echo "$TASK" | cut -c1-40)"
THREAD=$("$SWARM_DIR/create-topic.sh" "🤖 $TOPIC_NAME" "" "$AGENT" 2>/dev/null || echo "0")

# 4. Before screenshot
SCREENSHOT="/tmp/engine-before-${AGENT}-${THREAD}.png"
if [[ -n "$URL" ]]; then
  curl -sf "http://localhost:9222/screenshot?url=$URL&output=$SCREENSHOT" >/dev/null 2>&1 || true
fi

# 5. Build prompt
PREFIX="${AGENT}-${THREAD}"
PROMPT_FILE="$TASK_DIR/${PREFIX}.prompt"
cat > "$PROMPT_FILE" <<PROMPT
# Task for $AGENT
Project: $PROJECT_DIR
${URL:+URL: $URL}

## Task
$TASK

${LESSONS:+$LESSONS}

## Rules
- Work in $PROJECT_DIR
- Test your changes
- When done: mkdir -p /tmp/engine-steps && echo done > /tmp/engine-steps/${PREFIX}.done
PROMPT

# 6. Determine check command
CHECK="file_exists /tmp/engine-steps/${PREFIX}.done"
[[ -n "$URL" ]] && CHECK="http_status $URL 200"

# 7. Output JSON
jq -n --arg agent "$AGENT" --arg thread "$THREAD" \
  --arg prompt "$PROMPT_FILE" --arg check "$CHECK" \
  --arg screenshot "$SCREENSHOT" --arg label "$PREFIX" \
  --argjson lessons "$(echo "${LESSONS:-[]}" | jq -Rs 'split("\n") | map(select(length>0))')" \
  '{agent:$agent, thread:$thread, prompt_file:$prompt, check:$check, before_screenshot:$screenshot, label:$label, lessons:$lessons}'
