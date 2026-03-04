#!/bin/bash
# Save a message/event to Pieces LTM in real-time
# Usage: pieces-realtime.sh "source" "content"

SOURCE="${1:-unknown}"
CONTENT="${2:-}"
[ -z "$CONTENT" ] && exit 0

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PIECES_API="http://localhost:39300"

# Check Pieces is running (quick check)
curl -sf "$PIECES_API/.well-known/health" > /dev/null 2>&1 || exit 0

# Save via Pieces CLI
export DISPLAY=:1
echo "// [$TIMESTAMP] $SOURCE
$CONTENT" | xclip -selection clipboard 2>/dev/null
echo "y" | pieces create 2>/dev/null > /dev/null

# Also append to daily buffer
DAILY="/tmp/pieces-daily-$(date '+%Y%m%d').log"
echo "[$TIMESTAMP] $SOURCE: $CONTENT" >> "$DAILY"
