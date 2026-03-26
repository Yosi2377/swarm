#!/bin/bash
# rate-guard.sh — Wait if too many API calls recently
# Usage: source rate-guard.sh (or bash rate-guard.sh)
# Checks /tmp/api-call-timestamps and waits if needed

LOCK="/tmp/openclaw-rate-guard.lock"
CALLS_FILE="/tmp/openclaw-api-calls.log"

# Record this call
echo "$(date +%s)" >> "$CALLS_FILE"

# Count calls in last 60 seconds
NOW=$(date +%s)
RECENT=$(awk -v now="$NOW" '$1 > now-60' "$CALLS_FILE" 2>/dev/null | wc -l)

# If more than 3 calls in last minute, wait
if [ "$RECENT" -gt 3 ]; then
  WAIT=$((RECENT * 5))
  [ "$WAIT" -gt 30 ] && WAIT=30
  echo "Rate guard: $RECENT calls in last 60s, waiting ${WAIT}s..." >&2
  sleep "$WAIT"
fi

# Cleanup old entries (keep last 100)
tail -100 "$CALLS_FILE" > "${CALLS_FILE}.tmp" 2>/dev/null && mv "${CALLS_FILE}.tmp" "$CALLS_FILE"
