#!/bin/bash
# Watchdog — Monitor active tasks for stalls
# Runs continuously, checks every 2 minutes
# Usage: watchdog.sh [--once]  (--once for single check, no loop)

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SWARM_DIR/tasks"
LOG_DIR="$SWARM_DIR/logs"
QUEUE_DIR="/tmp/delegate-queue"
MEMORY_DIR="$SWARM_DIR/memory"
LOG_FILE="$LOG_DIR/watchdog.log"

mkdir -p "$LOG_DIR" "$QUEUE_DIR"

ONCE=false
[ "$1" = "--once" ] && ONCE=true

log() { echo "$(date -Is) $1" >> "$LOG_FILE"; }

get_field() { python3 -c "import json;d=json.load(open('$1'));print(d.get('$2',''))" 2>/dev/null; }
set_field() {
  python3 -c "
import json
f='$1'
d=json.load(open(f))
d['$2']=$3
json.dump(d,open(f,'w'),indent=2)
" 2>/dev/null
}

check_task() {
  local TF="$1"
  local TASK_ID=$(get_field "$TF" "task_id")
  local AGENT=$(get_field "$TF" "agent_id")
  local STEP=$(get_field "$TF" "current_step")
  local STATUS=$(get_field "$TF" "current_status")
  local THREAD=$(get_field "$TF" "thread_id")
  local RESTARTS=$(get_field "$TF" "restarts")

  # Only check active tasks not in done/review
  [ "$STEP" = "done" ] && return
  [ "$STATUS" != "active" ] && return

  # Find last activity: check memory dir mtime, log file, task file
  local NOW=$(date +%s)
  local LAST_ACTIVITY=0

  # Check agent memory dir
  if [ -d "$MEMORY_DIR/$AGENT" ]; then
    local MEM_TIME=$(find "$MEMORY_DIR/$AGENT" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
    [ -n "$MEM_TIME" ] && [ "$MEM_TIME" -gt "$LAST_ACTIVITY" ] && LAST_ACTIVITY=$MEM_TIME
  fi

  # Check task file mtime
  local TF_TIME=$(stat -c %Y "$TF" 2>/dev/null)
  [ -n "$TF_TIME" ] && [ "$TF_TIME" -gt "$LAST_ACTIVITY" ] && LAST_ACTIVITY=$TF_TIME

  # Check today's log
  local TODAY=$(date +%Y-%m-%d)
  local LOG="$LOG_DIR/$TODAY.jsonl"
  if [ -f "$LOG" ]; then
    local LOG_TIME=$(stat -c %Y "$LOG" 2>/dev/null)
    [ -n "$LOG_TIME" ] && [ "$LOG_TIME" -gt "$LAST_ACTIVITY" ] && LAST_ACTIVITY=$LOG_TIME
  fi

  [ "$LAST_ACTIVITY" -eq 0 ] && LAST_ACTIVITY=$(stat -c %Y "$TF" 2>/dev/null)
  local IDLE=$((NOW - LAST_ACTIVITY))
  local IDLE_MIN=$((IDLE / 60))

  # 5 min → ping
  if [ $IDLE_MIN -ge 5 ] && [ $IDLE_MIN -lt 10 ]; then
    if [ ! -f "$QUEUE_DIR/${AGENT}-ping.json" ]; then
      cat > "$QUEUE_DIR/${AGENT}-ping.json" <<EOF
{"type":"ping","agent":"$AGENT","task_id":"$TASK_ID","thread_id":"$THREAD","idle_min":$IDLE_MIN,"ts":"$(date -Is)"}
EOF
      log "PING: $AGENT idle ${IDLE_MIN}m on task $TASK_ID"
    fi
  fi

  # 10 min → restart
  if [ $IDLE_MIN -ge 10 ]; then
    rm -f "$QUEUE_DIR/${AGENT}-ping.json"
    if [ ! -f "$QUEUE_DIR/${AGENT}-restart.json" ]; then
      cat > "$QUEUE_DIR/${AGENT}-restart.json" <<EOF
{"type":"restart","agent":"$AGENT","task_id":"$TASK_ID","thread_id":"$THREAD","idle_min":$IDLE_MIN,"ts":"$(date -Is)"}
EOF
      RESTARTS=${RESTARTS:-0}
      set_field "$TF" "restarts" "$((RESTARTS + 1))"
      log "RESTART: $AGENT idle ${IDLE_MIN}m on task $TASK_ID (restart #$((RESTARTS + 1)))"

      # 3 restarts → escalate
      if [ $((RESTARTS + 1)) -ge 3 ]; then
        cat > "$QUEUE_DIR/escalate-${TASK_ID}.json" <<EOF
{"type":"escalate","agent":"$AGENT","task_id":"$TASK_ID","thread_id":"$THREAD","restarts":$((RESTARTS+1)),"ts":"$(date -Is)"}
EOF
        log "ESCALATE: task $TASK_ID after $((RESTARTS+1)) restarts"
      fi
    fi
  fi
}

check_all() {
  for TF in "$TASKS_DIR"/*.pipeline.json; do
    [ -f "$TF" ] && check_task "$TF"
  done
}

log "Watchdog started"

if $ONCE; then
  check_all
  echo "Watchdog check complete. See $LOG_FILE"
else
  while true; do
    check_all
    sleep 120
  done
fi
