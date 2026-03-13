#!/bin/bash
# orchestrate.sh — Route task to right agent, create topic, run
# Usage: orchestrate.sh <task_description> [project_dir] [--dry-run]
set -euo pipefail

TASK="${1:?Usage: orchestrate.sh <task_description> [project_dir] [--dry-run]}"
PROJECT_DIR="${2:-/root/.openclaw/workspace}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" || "${3:-}" == "--dry-run" ]] && DRY_RUN=true
[[ "${2:-}" == "--dry-run" ]] && PROJECT_DIR="/root/.openclaw/workspace"

SWARM_DIR="$(cd "$(dirname "$0")/../swarm" && pwd)"
V2_DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

# Route by keywords
pick_agent() {
  case "$TASK_LOWER" in
    *security*|*ssl*|*port*|*scan*|*אבטח*|*סריק*)       echo "shomer" ;;
    *design*|*ui*|*logo*|*image*|*עיצוב*|*תמונ*|*לוגו*) echo "tzayar" ;;
    *research*|*מחקר*|*best.practice*)                    echo "researcher" ;;
    *test*|*qa*|*בדיק*|*טסט*)                            echo "tester" ;;
    *data*|*mongo*|*sql*|*backup*|*דאטא*)                echo "data" ;;
    *debug*|*error*|*log*|*דיבאג*)                       echo "debugger" ;;
    *docker*|*container*|*k8s*|*devops*)                  echo "docker" ;;
    *frontend*|*html*|*css*|*פרונט*)                     echo "front" ;;
    *backend*|*api*|*server*|*באק*)                      echo "back" ;;
    *refactor*|*optimize*|*ריפקטור*)                     echo "refactor" ;;
    *monitor*|*alert*|*uptime*|*מוניטור*)                echo "monitor" ;;
    *performance*|*cache*|*speed*)                        echo "optimizer" ;;
    *webhook*|*integrat*|*אינטגר*)                       echo "integrator" ;;
    *)                                                    echo "koder" ;;
  esac
}

AGENT_ID=$(pick_agent)
SHORT_TASK=$(echo "$TASK" | head -c 40)

if $DRY_RUN; then
  echo "=== DRY RUN ==="
  echo "Agent: $AGENT_ID"
  echo "Task: $SHORT_TASK"
  echo "Project: $PROJECT_DIR"
  echo "Would: create topic → run agent-runner → verify → report"
  exit 0
fi

# Create topic
EMOJI_MAP="koder:⚙️ shomer:🔒 tzayar:🎨 researcher:🔍 tester:🧪 data:📊 debugger:🐛 docker:🐳 front:🖥️ back:⚡ refactor:♻️ monitor:📡 optimizer:🚀 integrator:🔗 worker:🤖"
EMOJI=$(echo "$EMOJI_MAP" | tr ' ' '\n' | grep "^${AGENT_ID}:" | cut -d: -f2)
EMOJI="${EMOJI:-🤖}"

THREAD_ID=$("$SWARM_DIR/create-topic.sh" "${EMOJI} ${SHORT_TASK}" "" "$AGENT_ID")

if [ -z "$THREAD_ID" ]; then
  echo "ERROR: Failed to create topic" >&2
  exit 1
fi

# Run agent
bash "$V2_DIR/agent-runner.sh" "$AGENT_ID" "$THREAD_ID" "$TASK" "$PROJECT_DIR"

# Report
"$SWARM_DIR/send.sh" or 1 "🐝 משימה חדשה: ${EMOJI} ${AGENT_ID} → ${SHORT_TASK} (topic ${THREAD_ID})"
echo "AGENT=$AGENT_ID THREAD=$THREAD_ID"
