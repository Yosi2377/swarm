#!/bin/bash
# screenshot.sh — Take screenshots at 3 viewports and send to Telegram
# Usage: screenshot.sh <url> <thread_id> <agent_id> [label]
set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
URL="${1:?Usage: screenshot.sh <url> <thread_id> <agent_id> [label]}"
THREAD="${2:?Missing thread_id}"
AGENT="${3:?Missing agent_id}"
LABEL="${4:-screenshot}"
CHAT_ID="-1003815143703"

# Resolve bot token
TOKEN_FILE="$SWARM_DIR/.${AGENT}-token"
if [ ! -f "$TOKEN_FILE" ]; then
  echo "❌ Token file not found: $TOKEN_FILE"
  exit 1
fi
TOKEN=$(cat "$TOKEN_FILE")

VIEWPORTS=("1920x1080:desktop" "768x1024:tablet" "375x812:mobile")
TAKEN=0

for vp in "${VIEWPORTS[@]}"; do
  IFS=':' read -r SIZE NAME <<< "$vp"
  W="${SIZE%x*}"
  H="${SIZE#*x}"
  OUTFILE="/tmp/browser-${LABEL}-${NAME}-${THREAD}.png"

  echo "📸 Capturing $NAME ($W×$H) → $OUTFILE"

  # Use Playwright via the openclaw browser tool (CLI fallback)
  # We use npx playwright screenshot with viewport
  npx --yes playwright screenshot \
    --viewport-size="${W},${H}" \
    --wait-for-timeout=3000 \
    --full-page \
    "$URL" "$OUTFILE" 2>/dev/null || {
    # Fallback: use chromium directly
    chromium-browser --headless --disable-gpu --no-sandbox \
      --screenshot="$OUTFILE" --window-size="${W},${H}" \
      "$URL" 2>/dev/null || {
      echo "⚠️ Failed to capture $NAME viewport"
      continue
    }
  }

  if [ -f "$OUTFILE" ] && [ -s "$OUTFILE" ]; then
    TAKEN=$((TAKEN + 1))
    echo "📤 Sending $NAME to Telegram thread $THREAD..."
    curl -sf -F "chat_id=$CHAT_ID" -F "message_thread_id=$THREAD" \
      -F "photo=@$OUTFILE" -F "caption=📸 ${LABEL} — ${NAME} (${W}×${H})" \
      "https://api.telegram.org/bot${TOKEN}/sendPhoto" > /dev/null || {
      echo "⚠️ Failed to send $NAME to Telegram"
    }
  fi
done

echo ""
if [ "$TAKEN" -ge 1 ]; then
  echo "✅ Captured $TAKEN/${#VIEWPORTS[@]} viewports"
  exit 0
else
  echo "❌ No screenshots captured!"
  exit 1
fi
