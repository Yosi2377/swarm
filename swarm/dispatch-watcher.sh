#!/bin/bash
# dispatch-watcher.sh — The heart of SwarmClaw automation
# Runs via cron every minute. Handles:
#   1. New dispatches in /tmp/dispatch-queue/ → spawn sub-agents via OpenClaw hook
#   2. Done agents in /tmp/agent-done/ → verify & report
#   3. Stuck agents (>15 min) → escalate
#
# Install: echo "* * * * * /root/.openclaw/workspace/swarm/dispatch-watcher.sh >> /tmp/dispatch-watcher.log 2>&1" | crontab -
#
# Can also run manually: bash dispatch-watcher.sh [--once]

set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
QUEUE_DIR="/tmp/dispatch-queue"
DONE_DIR="/tmp/agent-done"
META_DIR="/tmp/agent-tasks"
SPAWN_DIR="/tmp/spawn-request"
LOCK_FILE="/tmp/dispatch-watcher.lock"
MAX_RETRIES=3
STUCK_MINUTES=15

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
    if [ "$LOCK_AGE" -lt 55 ]; then
        exit 0  # Another instance running
    fi
    rm -f "$LOCK_FILE"  # Stale lock
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

mkdir -p "$QUEUE_DIR" "$DONE_DIR" "$META_DIR" "$SPAWN_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ─── OpenClaw Hook config ───
HOOK_TOKEN=$(python3 -c "import json; c=json.load(open('/root/.openclaw/openclaw.json')); print(c.get('hooks',{}).get('token',''))" 2>/dev/null)
HOOK_PORT=$(python3 -c "import json; c=json.load(open('/root/.openclaw/openclaw.json')); print(c.get('gateway',{}).get('port', c.get('port', 3120)))" 2>/dev/null || echo 3120)

spawn_via_hook() {
    local task_text="$1"
    local label="$2"
    local session_key="${3:-agent:main:telegram:group:-1003815143703:topic:1}"

    # Write spawn request for heartbeat pickup as fallback
    cat > "${SPAWN_DIR}/${label}.json" <<SEOF
{
    "task": $(echo "$task_text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
    "label": "${label}",
    "sessionKey": "${session_key}",
    "created_at": "$(date -Iseconds)"
}
SEOF

    # Try direct OpenClaw hook
    if [ -n "$HOOK_TOKEN" ]; then
        local result
        result=$(curl -sf -X POST "http://127.0.0.1:${HOOK_PORT}/hooks/agent-watcher" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${HOOK_TOKEN}" \
            -d "$(python3 -c "
import json, sys
task = open('${SPAWN_DIR}/${label}.json').read()
d = json.loads(task)
print(json.dumps({'task': d['task'], 'sessionKey': d['sessionKey']}))
")" 2>/dev/null)

        if echo "$result" | grep -q '"ok"'; then
            log "  ✅ Spawned via hook: ${label}"
            rm -f "${SPAWN_DIR}/${label}.json"
            return 0
        fi
    fi

    log "  ⚠️ Hook failed, spawn request saved for heartbeat pickup: ${label}"
    return 1
}

send_general() {
    bash "${SWARM_DIR}/send.sh" or 1 "$1" >/dev/null 2>&1
}

send_to_thread() {
    local agent="$1" thread="$2" msg="$3"
    bash "${SWARM_DIR}/send.sh" "$agent" "$thread" "$msg" >/dev/null 2>&1
}

# ═══════════════════════════════════════════
# PHASE 1: Process new dispatches
# ═══════════════════════════════════════════
for queue_file in "$QUEUE_DIR"/*.json; do
    [ -f "$queue_file" ] || continue
    
    TASK_ID=$(python3 -c "import json; print(json.load(open('$queue_file'))['task_id'])" 2>/dev/null)
    AGENT_ID=$(python3 -c "import json; print(json.load(open('$queue_file'))['agent_id'])" 2>/dev/null)
    THREAD_ID=$(python3 -c "import json; print(json.load(open('$queue_file'))['thread_id'])" 2>/dev/null)
    TASK_TEXT=$(python3 -c "import json; print(json.load(open('$queue_file'))['task_text'])" 2>/dev/null)
    
    if [ -z "$TASK_ID" ]; then
        log "⚠️ Invalid queue file: $queue_file"
        mv "$queue_file" "${queue_file}.invalid"
        continue
    fi

    log "🚀 Dispatching: ${TASK_ID}"
    
    # Update meta status
    META_FILE="${META_DIR}/${TASK_ID}.json"
    if [ -f "$META_FILE" ]; then
        python3 -c "
import json
m = json.load(open('$META_FILE'))
m['status'] = 'spawning'
m['spawn_at'] = '$(date -Iseconds)'
json.dump(m, open('$META_FILE','w'), indent=2)
" 2>/dev/null
    fi
    
    # Spawn sub-agent
    spawn_via_hook "$TASK_TEXT" "$TASK_ID" "agent:main:telegram:group:-1003815143703:topic:${THREAD_ID}"
    
    # Remove from queue (processed)
    mv "$queue_file" "${queue_file}.dispatched"
done

# ═══════════════════════════════════════════
# PHASE 2: Check done agents → verify
# ═══════════════════════════════════════════
for done_file in "$DONE_DIR"/*.json; do
    [ -f "$done_file" ] || continue
    
    # Check if already reported
    REPORTED=$(python3 -c "import json; print(json.load(open('$done_file')).get('reported', False))" 2>/dev/null)
    [ "$REPORTED" = "True" ] && continue
    
    LABEL=$(python3 -c "import json; d=json.load(open('$done_file')); print(d.get('label', d.get('thread','unknown')))" 2>/dev/null)
    THREAD=$(python3 -c "import json; d=json.load(open('$done_file')); print(d.get('topic', d.get('thread','')))" 2>/dev/null)
    AGENT_ID=$(python3 -c "import json; print(json.load(open('$done_file')).get('agent','or'))" 2>/dev/null)

    log "🔍 Verifying: ${LABEL}"
    
    # Find metadata
    META_FILE=""
    for mf in "${META_DIR}"/*"${THREAD}"*.json "${META_DIR}"/*"${LABEL}"*.json; do
        [ -f "$mf" ] && META_FILE="$mf" && break
    done

    URL="" TEST_CMD="" PROJECT_DIR="" EXPECT=""
    if [ -n "$META_FILE" ] && [ -f "$META_FILE" ]; then
        URL=$(python3 -c "import json; print(json.load(open('$META_FILE')).get('url',''))" 2>/dev/null)
        TEST_CMD=$(python3 -c "import json; print(json.load(open('$META_FILE')).get('test_cmd',''))" 2>/dev/null)
        PROJECT_DIR=$(python3 -c "import json; print(json.load(open('$META_FILE')).get('project_dir',''))" 2>/dev/null)
        EXPECT=$(python3 -c "import json; print(json.load(open('$META_FILE')).get('expect',''))" 2>/dev/null)
    fi

    # Build verify args
    VERIFY_ARGS=("$AGENT_ID" "$THREAD")
    [ -n "$URL" ] && VERIFY_ARGS+=(--url "$URL")
    [ -n "$TEST_CMD" ] && VERIFY_ARGS+=(--test "$TEST_CMD")
    [ -n "$PROJECT_DIR" ] && VERIFY_ARGS+=(--project "$PROJECT_DIR")
    [ -n "$EXPECT" ] && VERIFY_ARGS+=(--expect "$EXPECT")

    # Run verification
    VERIFY_OUTPUT=$(timeout 60 node "${SWARM_DIR}/runner/verify-and-report.js" "${VERIFY_ARGS[@]}" 2>&1) || true
    EXIT_CODE=$?

    if echo "$VERIFY_OUTPUT" | grep -q "RESULT=PASS"; then
        log "  ✅ PASS: ${LABEL}"
        
        # Update scores
        bash "${SWARM_DIR}/learn.sh" score "$AGENT_ID" success 2>/dev/null || true
        
        # Mark as reported
        python3 -c "
import json
d = json.load(open('$done_file'))
d['reported'] = True
d['verified'] = 'pass'
json.dump(d, open('$done_file','w'), indent=2)
" 2>/dev/null
        
        SUMMARY=$(python3 -c "import json; print(json.load(open('$done_file')).get('summary','done'))" 2>/dev/null)
        send_general "✅ ${AGENT_ID} #${THREAD} הושלם ואומת: ${SUMMARY}"
        
    elif echo "$VERIFY_OUTPUT" | grep -q "RESULT=ESCALATE"; then
        log "  🚨 ESCALATE: ${LABEL}"
        ISSUES=$(echo "$VERIFY_OUTPUT" | grep "ISSUES=" | sed 's/ISSUES=//')
        
        bash "${SWARM_DIR}/learn.sh" score "$AGENT_ID" fail 2>/dev/null || true
        
        python3 -c "
import json
d = json.load(open('$done_file'))
d['reported'] = True
d['verified'] = 'escalated'
json.dump(d, open('$done_file','w'), indent=2)
" 2>/dev/null
        
        send_general "🚨 ${AGENT_ID} #${THREAD} נכשל 3 פעמים — צריך עזרה ידנית. בעיות: ${ISSUES}"
        
    elif echo "$VERIFY_OUTPUT" | grep -q "RESULT=RETRY"; then
        log "  🔄 RETRY: ${LABEL}"
        ISSUES=$(echo "$VERIFY_OUTPUT" | grep "ISSUES=" | sed 's/ISSUES=//')
        RETRIES=$(python3 -c "import json; print(json.load(open('${META_FILE:-/dev/null}')).get('retries',0))" 2>/dev/null || echo 0)
        
        # Re-dispatch with error context
        if [ -n "$META_FILE" ] && [ -f "$META_FILE" ]; then
            TASK_DESC=$(python3 -c "import json; print(json.load(open('$META_FILE')).get('task_desc',''))" 2>/dev/null)
            RETRY_TASK="RETRY (${RETRIES}/3): ${TASK_DESC}\n\nPrevious attempt failed:\n${ISSUES}\n\nFix these issues and try again."
            
            RETRY_TEXT=$(bash "${SWARM_DIR}/spawn-agent.sh" "$AGENT_ID" "$THREAD" "$RETRY_TASK" "$TEST_CMD" "$PROJECT_DIR")
            spawn_via_hook "$RETRY_TEXT" "${LABEL}-retry${RETRIES}" "agent:main:telegram:group:-1003815143703:topic:${THREAD}"
        fi
        
        # Mark this done file as handled (new done will come from retry)
        python3 -c "
import json
d = json.load(open('$done_file'))
d['reported'] = True
d['verified'] = 'retrying'
json.dump(d, open('$done_file','w'), indent=2)
" 2>/dev/null
    fi
done

# ═══════════════════════════════════════════
# PHASE 3: Check for stuck agents (>15 min)
# ═══════════════════════════════════════════
NOW=$(date +%s)
for meta_file in "$META_DIR"/*.json; do
    [ -f "$meta_file" ] || continue
    
    STATUS=$(python3 -c "import json; print(json.load(open('$meta_file')).get('status',''))" 2>/dev/null)
    [ "$STATUS" = "running" ] || [ "$STATUS" = "spawning" ] || continue
    
    DISPATCHED=$(python3 -c "
import json, datetime
d = json.load(open('$meta_file'))
t = d.get('spawn_at', d.get('dispatched_at', ''))
if t:
    dt = datetime.datetime.fromisoformat(t.replace('Z','+00:00'))
    print(int(dt.timestamp()))
else:
    print(0)
" 2>/dev/null || echo 0)
    
    if [ "$DISPATCHED" -gt 0 ]; then
        AGE_MIN=$(( (NOW - DISPATCHED) / 60 ))
        if [ "$AGE_MIN" -ge "$STUCK_MINUTES" ]; then
            TASK_ID=$(python3 -c "import json; print(json.load(open('$meta_file')).get('task_id','unknown'))" 2>/dev/null)
            THREAD_ID=$(python3 -c "import json; print(json.load(open('$meta_file')).get('thread_id',''))" 2>/dev/null)
            
            # Check if already flagged
            FLAGGED=$(python3 -c "import json; print(json.load(open('$meta_file')).get('stuck_flagged', False))" 2>/dev/null)
            [ "$FLAGGED" = "True" ] && continue
            
            log "⏰ STUCK (${AGE_MIN}m): ${TASK_ID}"
            
            python3 -c "
import json
m = json.load(open('$meta_file'))
m['stuck_flagged'] = True
m['stuck_at'] = '$(date -Iseconds)'
json.dump(m, open('$meta_file','w'), indent=2)
" 2>/dev/null
            
            send_general "⏰ סוכן ${TASK_ID} תקוע כבר ${AGE_MIN} דקות (thread ${THREAD_ID})"
        fi
    fi
done

# ═══════════════════════════════════════════
# PHASE 4: Check spawn requests (heartbeat fallback)
# ═══════════════════════════════════════════
SPAWN_COUNT=$(ls "$SPAWN_DIR"/*.json 2>/dev/null | wc -l)
if [ "$SPAWN_COUNT" -gt 0 ]; then
    log "📬 ${SPAWN_COUNT} pending spawn requests (waiting for heartbeat)"
fi

log "✓ Watcher cycle complete"
