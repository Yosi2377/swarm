#!/bin/bash
# monitor-daemon.sh — Background daemon checking for completed agents
# Usage: monitor-daemon.sh [--once]  (--once for single pass)
set -uo pipefail

V2_DIR="$(cd "$(dirname "$0")" && pwd)"
SWARM_DIR="$(cd "$(dirname "$0")/../swarm" && pwd)"
DONE_DIR="/tmp/agent-done"
VERIFIED_DIR="/tmp/agent-verified"
ONCE=false
[[ "${1:-}" == "--once" ]] && ONCE=true

mkdir -p "$DONE_DIR" "$VERIFIED_DIR"

check_once() {
  for f in "$DONE_DIR"/*.json; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f" .json)
    
    # Skip already verified
    [ -f "$VERIFIED_DIR/$BASENAME" ] && continue
    
    # Parse agent_id and thread_id from filename (format: agent-thread.json)
    AGENT_ID=$(echo "$BASENAME" | rev | cut -d- -f2- | rev)
    THREAD_ID=$(echo "$BASENAME" | rev | cut -d- -f1 | rev)
    
    # Validate
    [ -z "$AGENT_ID" ] || [ -z "$THREAD_ID" ] && continue
    
    echo "[$(date +%H:%M:%S)] Verifying: $AGENT_ID thread $THREAD_ID"
    
    if bash "$V2_DIR/verify.sh" "$AGENT_ID" "$THREAD_ID" 2>&1; then
      STATUS=$(jq -r '.status // "unknown"' "$f" 2>/dev/null || echo "unknown")
      SUMMARY=$(jq -r '.summary // "done"' "$f" 2>/dev/null || echo "done")
      "$SWARM_DIR/send.sh" or 1 "✅ ${AGENT_ID} (${THREAD_ID}): ${SUMMARY}" 2>/dev/null || true
    else
      "$SWARM_DIR/send.sh" or 1 "❌ ${AGENT_ID} (${THREAD_ID}): verify failed" 2>/dev/null || true
    fi
    
    # Mark as verified
    touch "$VERIFIED_DIR/$BASENAME"
  done
}

if $ONCE; then
  check_once
  exit 0
fi

echo "Monitor daemon started (PID $$). Checking every 60s..."
while true; do
  check_once
  sleep 60
done
