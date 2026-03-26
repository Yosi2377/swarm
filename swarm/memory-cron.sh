#!/bin/bash
# memory-cron.sh — Runs every 30 min to save session memory
# Also syncs to Pieces if available

# Save session contexts to topic files
bash /root/.openclaw/workspace/swarm/auto-memory-save.sh

# Save to Pieces if running
if curl -sf http://localhost:39300/.well-known/health > /dev/null 2>&1; then
  # Read latest daily buffer and push to Pieces
  DAILY="/tmp/pieces-daily-$(date '+%Y%m%d').log"
  if [ -f "$DAILY" ]; then
    LAST_SYNC="/tmp/pieces-last-sync"
    if [ -f "$LAST_SYNC" ]; then
      NEWER=$(find "$DAILY" -newer "$LAST_SYNC" 2>/dev/null)
      [ -z "$NEWER" ] && exit 0
    fi
    # Push to pieces
    export DISPLAY=:1
    tail -20 "$DAILY" | pieces create 2>/dev/null > /dev/null
    touch "$LAST_SYNC"
  fi
fi
