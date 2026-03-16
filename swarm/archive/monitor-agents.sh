#!/bin/bash
# Monitor Agents — Alerting system for failed/stuck agents
# Scans /tmp/agent-tasks/*.json for status issues
# Sends alerts via send.sh to General (topic 1)

TASKS_DIR="/tmp/agent-tasks"
ALERTS_LOG="/root/.openclaw/workspace/swarm/logs/alerts.jsonl"
SEND_SH="/root/.openclaw/workspace/swarm/send.sh"
FAIL_THRESHOLD=3
STUCK_MINUTES=15
NOW=$(date +%s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$ALERTS_LOG")" "$TASKS_DIR"

# Track failures per agent
declare -A FAIL_COUNT
declare -A STUCK_AGENTS

shopt -s nullglob
for f in "$TASKS_DIR"/*.json; do
    [ -f "$f" ] || continue
    
    status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null)
    agent=$(jq -r '.agent // .agent_id // "unknown"' "$f" 2>/dev/null)
    task_id=$(basename "$f" .json)
    
    # Count failures
    if [ "$status" = "failed" ] || [ "$status" = "error" ]; then
        FAIL_COUNT[$agent]=$(( ${FAIL_COUNT[$agent]:-0} + 1 ))
    fi
    
    # Check stuck (running > 15 min)
    if [ "$status" = "running" ]; then
        started=$(jq -r '.started_at // .created_at // ""' "$f" 2>/dev/null)
        if [ -n "$started" ] && [ "$started" != "null" ]; then
            started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
            if [ "$started_epoch" -gt 0 ]; then
                elapsed_min=$(( (NOW - started_epoch) / 60 ))
                if [ "$elapsed_min" -ge "$STUCK_MINUTES" ]; then
                    STUCK_AGENTS[$agent]="${STUCK_AGENTS[$agent]}${task_id}(${elapsed_min}m) "
                fi
            fi
        else
            # Fallback: use file modification time
            file_epoch=$(stat -c %Y "$f" 2>/dev/null || echo 0)
            if [ "$file_epoch" -gt 0 ]; then
                elapsed_min=$(( (NOW - file_epoch) / 60 ))
                if [ "$elapsed_min" -ge "$STUCK_MINUTES" ]; then
                    STUCK_AGENTS[$agent]="${STUCK_AGENTS[$agent]}${task_id}(${elapsed_min}m) "
                fi
            fi
        fi
    fi
done

ALERTS_SENT=0

# Alert on agents with 3+ failures
for agent in "${!FAIL_COUNT[@]}"; do
    count=${FAIL_COUNT[$agent]}
    if [ "$count" -ge "$FAIL_THRESHOLD" ]; then
        msg="🚨 Alert: סוכן *${agent}* נכשל ${count} פעמים!"
        echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"failure\",\"agent\":\"$agent\",\"count\":$count}" >> "$ALERTS_LOG"
        bash "$SEND_SH" monitor 1 "$msg" 2>/dev/null
        ALERTS_SENT=$((ALERTS_SENT + 1))
    fi
done

# Alert on stuck agents
for agent in "${!STUCK_AGENTS[@]}"; do
    tasks="${STUCK_AGENTS[$agent]}"
    msg="⏰ Alert: סוכן *${agent}* תקוע! משימות: ${tasks}"
    echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"stuck\",\"agent\":\"$agent\",\"tasks\":\"$tasks\"}" >> "$ALERTS_LOG"
    bash "$SEND_SH" monitor 1 "$msg" 2>/dev/null
    ALERTS_SENT=$((ALERTS_SENT + 1))
done

# Log scan summary
total_files=$(ls "$TASKS_DIR"/*.json 2>/dev/null | wc -l)
echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"scan\",\"files\":$total_files,\"alerts\":$ALERTS_SENT}" >> "$ALERTS_LOG"

# Dedup: don't re-alert for same agent within 30 minutes
DEDUP_FILE="/tmp/monitor-last-alert.json"
should_alert() {
    local agent="$1"
    local now=$(date +%s)
    if [ -f "$DEDUP_FILE" ]; then
        local last=$(python3 -c "import json; d=json.load(open('$DEDUP_FILE')); print(d.get('$agent',0))" 2>/dev/null)
        local diff=$((now - last))
        [ "$diff" -lt 1800 ] && return 1
    fi
    python3 -c "
import json,os
f='$DEDUP_FILE'
d=json.load(open(f)) if os.path.exists(f) else {}
d['$agent']=$(date +%s)
json.dump(d,open(f,'w'))
"
    return 0
}
