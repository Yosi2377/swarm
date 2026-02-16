#!/bin/bash
# mission.sh — THE ONLY WAY TO RUN A TASK
# Enforces: topic → agents → send.sh updates → shomer → bodek → screenshot → user approval
# Usage: mission.sh "<description>" <project> <agent1> [agent2...]
# Example: mission.sh "אנימציית גול" betting koder tzayar

set -euo pipefail

DESC="$1"
PROJECT="$2"
shift 2
AGENTS=("$@")

CHAT="-1003815143703"
BOT_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token)
SWARM="/root/.openclaw/workspace/swarm"
LOG_DIR="/tmp/mission-logs"
mkdir -p "$LOG_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[MISSION]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ============================================
# STEP 1: Create Telegram Topic (MANDATORY)
# ============================================
log "STEP 1: Creating Telegram topic..."
EMOJI="⚙️"
[[ "${AGENTS[0]}" == "shomer" ]] && EMOJI="🔒"
[[ "${AGENTS[0]}" == "tzayar" ]] && EMOJI="🎨"
[[ "${AGENTS[0]}" == "researcher" ]] && EMOJI="🔍"
[[ "${AGENTS[0]}" == "worker" ]] && EMOJI="🤖"
[[ "${AGENTS[0]}" == "bodek" ]] && EMOJI="🧪"

THREAD=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/createForumTopic" \
  -d "chat_id=${CHAT}" -d "name=${EMOJI} ${DESC}" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['message_thread_id'])")

[ -z "$THREAD" ] && fail "Could not create topic!"
log "Topic created: #${THREAD}"

# ============================================
# STEP 2: Create task file (MANDATORY)
# ============================================
log "STEP 2: Creating task file..."
cat > "${SWARM}/tasks/${THREAD}.md" << EOF
# Task ${THREAD} — ${DESC}
**Project:** ${PROJECT}
**Agents:** ${AGENTS[*]}
**Created:** $(date '+%Y-%m-%d %H:%M')
**Status:** active

## Description
${DESC}

## Sandbox
URL: http://95.111.247.22:9089
Path: /root/sandbox/BettingPlatform
EOF
log "Task file: swarm/tasks/${THREAD}.md"

# ============================================
# STEP 3: Start sandbox (MANDATORY)
# ============================================
log "STEP 3: Starting sandbox..."
if [[ "$PROJECT" == *"betting"* || "$PROJECT" == *"Betting"* ]]; then
  systemctl start sandbox-betting-backend 2>/dev/null || true
  sleep 2
  systemctl is-active sandbox-betting-backend > /dev/null && log "Sandbox running ✅" || warn "Sandbox may not be running"
fi

# ============================================
# STEP 4: Announce in General (MANDATORY)
# ============================================
log "STEP 4: Announcing in General..."
AGENT_LIST=""
for a in "${AGENTS[@]}"; do
  case "$a" in
    koder) AGENT_LIST+="⚙️ קודר\n" ;;
    shomer) AGENT_LIST+="🔒 שומר\n" ;;
    tzayar) AGENT_LIST+="🎨 צייר\n" ;;
    researcher) AGENT_LIST+="🔍 חוקר\n" ;;
    worker) AGENT_LIST+="🤖 עובד\n" ;;
    bodek) AGENT_LIST+="🧪 בודק\n" ;;
  esac
done

${SWARM}/send.sh or 1 "🐝 <b>משימה #${THREAD}:</b> ${DESC}

סוכנים:
${AGENT_LIST}
📂 sandbox | Flow מלא" 2>/dev/null

log "Announced ✅"

# ============================================
# STEP 5: Activate agents (MANDATORY)
# ============================================
log "STEP 5: Activating ${#AGENTS[@]} agents..."

PIDS=()
LABELS=()

for agent in "${AGENTS[@]}"; do
  LABEL="task-${THREAD}-${agent}"
  LABELS+=("$LABEL")
  
  # Send start message via agent's bot
  ${SWARM}/send.sh "$agent" "$THREAD" "⏳ מתחיל לעבוד על: ${DESC}" 2>/dev/null
  
  log "Agent ${agent} announced in topic ✅"
done

# Output for orchestrator to use with sessions_spawn
echo ""
echo "============================================"
echo "THREAD=${THREAD}"
echo "TASK_FILE=${SWARM}/tasks/${THREAD}.md"
echo ""
echo "Next steps for orchestrator (אור):"
echo "1. sessions_spawn for each agent with label task-${THREAD}-<agent>"
echo "2. Each agent MUST use send.sh to post updates"
echo "3. After agents done → run: mission.sh review ${THREAD} ${PROJECT}"
echo "============================================"

# Save mission state
cat > "/tmp/mission-${THREAD}.json" << EOF
{
  "thread": ${THREAD},
  "desc": "${DESC}",
  "project": "${PROJECT}",
  "agents": $(printf '%s\n' "${AGENTS[@]}" | python3 -c "import sys,json;print(json.dumps([l.strip() for l in sys.stdin]))"),
  "status": "agents_working",
  "created": "$(date -Iseconds)",
  "steps_completed": ["topic","task_file","sandbox","announce","agents_started"],
  "steps_remaining": ["agents_done","shomer_review","bodek_test","screenshot","user_approval","deploy"]
}
EOF

log "Mission state saved to /tmp/mission-${THREAD}.json"
echo "$THREAD"
