#!/bin/bash
# parallel-dispatch.sh — Run multiple auto-flow instances in parallel
# Usage: parallel-dispatch.sh
# Reads from /tmp/dispatch-queue.json: [{"agent":"koder","thread":123,"project":"betting","desc":"..."},...]
#
# Or call directly:
#   parallel-dispatch.sh <agent1> <thread1> <project1> <desc1> -- <agent2> <thread2> <project2> <desc2>

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS=()
THREADS=()
AGENTS=()

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Parse arguments: agent thread project desc -- agent thread project desc
tasks=()
current=()
for arg in "$@"; do
  if [ "$arg" = "--" ]; then
    tasks+=("$(IFS='|'; echo "${current[*]}")")
    current=()
  else
    current+=("$arg")
  fi
done
[ ${#current[@]} -gt 0 ] && tasks+=("$(IFS='|'; echo "${current[*]}")")

if [ ${#tasks[@]} -eq 0 ]; then
  echo "Usage: parallel-dispatch.sh <agent> <thread> <project> <desc> [-- <agent> <thread> <project> <desc> ...]"
  exit 1
fi

log "🚀 Dispatching ${#tasks[@]} tasks in parallel..."

for task in "${tasks[@]}"; do
  IFS='|' read -r agent thread project desc <<< "$task"
  log "  → $agent #$thread ($project): $desc"
  
  nohup "$SWARM_DIR/auto-flow.sh" "$agent" "$thread" "$project" "$desc" \
    > "/tmp/auto-flow-${thread}.log" 2>&1 &
  
  PIDS+=($!)
  THREADS+=("$thread")
  AGENTS+=("$agent")
done

log "⏳ Waiting for all tasks to complete..."
log "PIDs: ${PIDS[*]}"

# Monitor all in parallel
DONE=0
TOTAL=${#PIDS[@]}
RESULTS=()

while [ $DONE -lt $TOTAL ]; do
  sleep 15
  for i in "${!PIDS[@]}"; do
    [ -z "${PIDS[$i]}" ] && continue
    if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
      wait "${PIDS[$i]}" 2>/dev/null
      RC=$?
      THREAD="${THREADS[$i]}"
      AGENT="${AGENTS[$i]}"
      
      if grep -q "EVALUATION PASSED" "/tmp/auto-flow-${THREAD}.log" 2>/dev/null; then
        log "✅ #$THREAD ($AGENT) — PASSED"
        RESULTS+=("✅ #$THREAD ($AGENT)")
      else
        log "❌ #$THREAD ($AGENT) — FAILED (exit $RC)"
        RESULTS+=("❌ #$THREAD ($AGENT)")
      fi
      
      PIDS[$i]=""
      DONE=$((DONE + 1))
    fi
  done
  
  RUNNING=$((TOTAL - DONE))
  [ $RUNNING -gt 0 ] && log "⏳ $RUNNING/$TOTAL still running..."
done

log "🏁 All done!"
for r in "${RESULTS[@]}"; do
  log "  $r"
done

# Send summary to General
TOKEN=$(cat "$SWARM_DIR/.bot-token" 2>/dev/null)
if [ -n "$TOKEN" ]; then
  SUMMARY="🏁 Parallel dispatch done:\n"
  for r in "${RESULTS[@]}"; do
    SUMMARY+="$r\n"
  done
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=-1003815143703" \
    -d "message_thread_id=1" \
    -d "text=$(echo -e "$SUMMARY")" >/dev/null 2>&1
fi
