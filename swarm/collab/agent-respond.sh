#!/bin/bash
# agent-respond.sh — Get AI response via Claude through OpenClaw gateway
# ZERO external APIs. 100% Claude.
PROMPT_FILE="$1"
[ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ] && exit 1

PROMPT=$(cat "$PROMPT_FILE")

# Rate guard — wait if too many recent calls
bash "$(dirname "$0")/../rate-guard.sh" 2>/dev/null

# Call the main OpenClaw agent with a longer timeout and minimal thinking to
# reduce template fallbacks during collab sessions.
RESULT=$(timeout 180 openclaw agent --agent main --thinking minimal --timeout 170 -m "$PROMPT" --json 2>/dev/null)

echo "$RESULT" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    payloads = d.get('result',{}).get('payloads',[])
    if payloads:
        print(payloads[0].get('text',''))
except:
    pass
" 2>/dev/null
