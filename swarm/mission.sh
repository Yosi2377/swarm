#!/bin/bash
# mission.sh — THE ONLY WAY TO RUN A TASK
# Integrates ALL swarm tools into one enforced flow
# Usage: mission.sh "<description>" <project> <agent1> [agent2...]

set -euo pipefail

DESC="$1"
PROJECT="$2"
shift 2
AGENTS=("$@")

CHAT="-1003815143703"
SWARM="/root/.openclaw/workspace/swarm"
BOT_TOKEN=$(cat ${SWARM}/.bot-token)

log() { echo -e "\033[0;32m[MISSION]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1"; exit 1; }

# ============================================
# STEP 1: Create Telegram Topic
# ============================================
log "STEP 1: Creating topic..."
EMOJI="⚙️"
case "${AGENTS[0]}" in
  shomer) EMOJI="🔒" ;; tzayar) EMOJI="🎨" ;; researcher) EMOJI="🔍" ;;
  worker) EMOJI="🤖" ;; bodek) EMOJI="🧪" ;;
esac

THREAD=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/createForumTopic" \
  -d "chat_id=${CHAT}" -d "name=${EMOJI} ${DESC}" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['message_thread_id'])")
[ -z "$THREAD" ] && fail "Could not create topic!"
log "Topic #${THREAD} ✅"

# ============================================
# STEP 2: Register task (task.sh)
# ============================================
log "STEP 2: Registering task..."
${SWARM}/task.sh add "${AGENTS[0]}" "$THREAD" "$DESC" 2>/dev/null || true

# Create task file
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

## Dependencies
- depends_on: none
- blocks: none
EOF
log "Task file ✅"

# ============================================
# STEP 3: Start sandbox + sync DB
# ============================================
log "STEP 3: Sandbox..."
if [[ "$PROJECT" == *"betting"* || "$PROJECT" == *"Betting"* ]]; then
  systemctl start sandbox-betting-backend 2>/dev/null || true
  # Sync DB
  ${SWARM}/sync-sandbox-db.sh 2>/dev/null || true
  sleep 2
fi
log "Sandbox ready ✅"

# ============================================
# STEP 4: Checkpoint (save safe state)
# ============================================
log "STEP 4: Checkpoint..."
${SWARM}/checkpoint.sh save "$THREAD" "pre-work" '{"desc":"'"$DESC"'"}' 2>/dev/null || true
log "Checkpoint saved ✅"

# ============================================
# STEP 5: Learning — query past lessons
# ============================================
log "STEP 5: Learning query..."
LESSONS=$(${SWARM}/learn.sh query "$DESC" 2>/dev/null || echo "no lessons")
log "Past lessons: ${LESSONS:0:100}"

# ============================================
# STEP 6: Update status dashboard
# ============================================
log "STEP 6: Status dashboard..."
for agent in "${AGENTS[@]}"; do
  ${SWARM}/update-status.sh "$agent" "$THREAD" working "$DESC" 2>/dev/null || true
done
log "Dashboard updated ✅"

# ============================================
# STEP 7: Announce in General
# ============================================
log "STEP 7: Announcing..."
AGENT_LIST=""
for a in "${AGENTS[@]}"; do
  case "$a" in
    koder) AGENT_LIST+="⚙️ קודר " ;; shomer) AGENT_LIST+="🔒 שומר " ;;
    tzayar) AGENT_LIST+="🎨 צייר " ;; researcher) AGENT_LIST+="🔍 חוקר " ;;
    worker) AGENT_LIST+="🤖 עובד " ;; bodek) AGENT_LIST+="🧪 בודק " ;;
  esac
done

${SWARM}/send.sh or 1 "🐝 <b>משימה #${THREAD}:</b> ${DESC}
סוכנים: ${AGENT_LIST}
📂 sandbox | Flow מלא" 2>/dev/null
log "Announced ✅"

# ============================================
# STEP 8: Activate agents + send to topic
# ============================================
log "STEP 8: Activating agents..."
for agent in "${AGENTS[@]}"; do
  ${SWARM}/send.sh "$agent" "$THREAD" "📋 <b>משימה:</b> ${DESC}

⛔ חובה:
1. עבוד ב-sandbox בלבד
2. send.sh ${agent} ${THREAD} עדכון כל 2 דקות
3. screenshot לפני done
4. commit כל שינוי" 2>/dev/null
  log "Agent ${agent} notified in topic ✅"
done

# ============================================
# STEP 9: Launch watch-task (auto-reporting)
# ============================================
log "STEP 9: Watch-task..."
FIRST_AGENT="${AGENTS[0]}"
nohup ${SWARM}/watch-task.sh "task-${THREAD}" "$THREAD" "$PROJECT" "$DESC" "$FIRST_AGENT" > "/tmp/watch-${THREAD}.log" 2>&1 &
WATCH_PID=$!
log "Watch-task PID: ${WATCH_PID} ✅"

# ============================================
# STEP 10: Launch progress reporter
# ============================================
log "STEP 10: Progress reporter..."
nohup ${SWARM}/progress.sh "$FIRST_AGENT" "$THREAD" "$DESC" > "/tmp/progress-${THREAD}.log" 2>&1 &
PROG_PID=$!
log "Progress PID: ${PROG_PID} ✅"

# ============================================
# Save mission state
# ============================================
cat > "/tmp/mission-${THREAD}.json" << EOF
{
  "thread": ${THREAD},
  "desc": "${DESC}",
  "project": "${PROJECT}",
  "agents": $(printf '%s\n' "${AGENTS[@]}" | python3 -c "import sys,json;print(json.dumps([l.strip() for l in sys.stdin]))"),
  "status": "agents_working",
  "watch_pid": ${WATCH_PID},
  "progress_pid": ${PROG_PID},
  "created": "$(date -Iseconds)",
  "steps_completed": ["topic","task_file","sandbox","checkpoint","learning_query","status_dashboard","announce","agents_activated","watch_task","progress"],
  "steps_remaining": ["agents_done","evaluator","shomer_review","bodek_test","screenshot","learning_record","user_approval","deploy"]
}
EOF

log "============================================"
log "✅ MISSION #${THREAD} LAUNCHED"
log ""
log "Next: orchestrator runs sessions_spawn per agent"
log "Then: mission-review.sh ${THREAD} ${PROJECT}"
log "============================================"
echo "$THREAD"
