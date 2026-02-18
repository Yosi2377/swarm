#!/bin/bash
# supervisor-check.sh — Check agent status and report changes
# Designed to be called by cron every 60s
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/tmp/supervisor-state.json"
REPORTED_FILE="/tmp/supervisor-reported.txt"

touch "$REPORTED_FILE"

# Get current subagents via OpenClaw CLI (sessions list)
# We use the gateway API directly
GW_TOKEN="a70b2c01b30494f2a6edf62a7d86f148c8e5b5572eb838de"
GW_URL="http://127.0.0.1:18789"

# Get active sessions
RESPONSE=$(curl -s "$GW_URL/api/sessions?kinds=subagent&activeMinutes=30&messageLimit=0" \
  -H "Authorization: Bearer $GW_TOKEN" 2>/dev/null)

if [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | jq . >/dev/null 2>&1; then
  exit 0
fi

# Parse active and recent
ACTIVE=$(echo "$RESPONSE" | jq -r '.sessions[]? | select(.status=="running") | .label // .sessionKey' 2>/dev/null)
DONE=$(echo "$RESPONSE" | jq -r '.sessions[]? | select(.status!="running") | "\(.label // .sessionKey)|\(.runtimeMs // 0)"' 2>/dev/null)

# Report new completions
while IFS='|' read -r LABEL RUNTIME_MS; do
  [ -z "$LABEL" ] && continue
  if ! grep -qF "$LABEL" "$REPORTED_FILE" 2>/dev/null; then
    MINS=$(( (RUNTIME_MS + 500) / 60000 ))
    "$SCRIPT_DIR/send.sh" or 1 "✅ ${LABEL} הושלם (${MINS}m)" 2>/dev/null
    echo "$LABEL" >> "$REPORTED_FILE"
  fi
done <<< "$DONE"

# Report active agents
while read -r LABEL; do
  [ -z "$LABEL" ] && continue
  "$SCRIPT_DIR/send.sh" or 1 "🔄 ${LABEL} רץ..." 2>/dev/null
done <<< "$ACTIVE"

# Health checks
for SVC in betting-backend betting-aggregator; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    "$SCRIPT_DIR/send.sh" or 1 "🔴 $SVC DOWN!" 2>/dev/null
  fi
done

# Clean old reported (keep last 50)
tail -50 "$REPORTED_FILE" > "$REPORTED_FILE.tmp" && mv "$REPORTED_FILE.tmp" "$REPORTED_FILE"
