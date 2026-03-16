#!/bin/bash
# agent-watchdog.sh — Monitors a sub-agent, restarts if it dies
# Usage: agent-watchdog.sh <label> <thread_id> <max_restarts> "<task_prompt>"
# Runs in background, checks every 30s

LABEL="$1"
THREAD="$2"
MAX_RESTARTS="${3:-3}"
TASK_PROMPT="$4"
SWARM="/root/.openclaw/workspace/swarm"

RESTARTS=0
CHECK_INTERVAL=30

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🐕 Watchdog started for ${LABEL} (max restarts: ${MAX_RESTARTS})"

while true; do
  sleep $CHECK_INTERVAL
  
  # Check if agent session is still active
  STATUS=$(openclaw session list --json 2>/dev/null | python3 -c "
import sys,json
try:
  data = json.load(sys.stdin)
  for s in data.get('sessions',[]):
    if s.get('label') == '${LABEL}':
      if s.get('stopReason') == 'stop':
        print('DONE')
      elif s.get('abortedLastRun'):
        print('ABORTED')
      else:
        print('RUNNING')
      sys.exit()
  print('NOT_FOUND')
except:
  print('ERROR')
" 2>/dev/null || echo "CHECK_FAILED")

  case "$STATUS" in
    RUNNING)
      # All good
      ;;
    DONE)
      log "✅ ${LABEL} finished successfully"
      ${SWARM}/send.sh or 1 "✅ ${LABEL} סיים!" 2>/dev/null
      break
      ;;
    ABORTED|NOT_FOUND|ERROR|CHECK_FAILED)
      RESTARTS=$((RESTARTS + 1))
      log "⚠️ ${LABEL} died (${STATUS}). Restart ${RESTARTS}/${MAX_RESTARTS}"
      
      if [ $RESTARTS -gt $MAX_RESTARTS ]; then
        log "❌ Max restarts reached. Alerting."
        ${SWARM}/send.sh or 1 "❌ ${LABEL} נפל ${MAX_RESTARTS} פעמים — צריך בדיקה ידנית" 2>/dev/null
        break
      fi
      
      ${SWARM}/send.sh or "$THREAD" "⚠️ סוכן נפל (${STATUS}), מפעיל מחדש... (${RESTARTS}/${MAX_RESTARTS})" 2>/dev/null
      
      # Restart via sessions_spawn would need orchestrator — instead, write to a restart queue
      echo "{\"label\":\"${LABEL}\",\"thread\":${THREAD},\"restart\":${RESTARTS},\"time\":\"$(date -Iseconds)\",\"task\":\"${TASK_PROMPT}\"}" > "/tmp/agent-restart-${LABEL}.json"
      
      log "Restart queued"
      ;;
  esac
done

log "🐕 Watchdog exiting for ${LABEL}"
