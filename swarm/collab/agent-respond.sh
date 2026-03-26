#!/bin/bash
# agent-respond.sh — Get AI response for collab agent via Gemini 2.5 Flash
PROMPT_FILE="$1"
[ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ] && exit 1

GEMINI_KEY=""
for ef in /root/BotVerse/.env /root/.env; do
  [ -f "$ef" ] && GEMINI_KEY=$(grep GEMINI_API_KEY "$ef" | cut -d= -f2) && [ -n "$GEMINI_KEY" ] && break
done
[ -z "$GEMINI_KEY" ] && exit 1

PROMPT=$(python3 -c "import sys,json; print(json.dumps(open(sys.argv[1]).read()))" "$PROMPT_FILE" 2>/dev/null)

curl -sf -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":$PROMPT}]}],\"generationConfig\":{\"maxOutputTokens\":500,\"temperature\":0.8,\"thinkingConfig\":{\"thinkingBudget\":0}}}" \
  2>/dev/null | python3 -c "
import sys,json
try:
    j=json.load(sys.stdin)
    print(j['candidates'][0]['content']['parts'][0]['text'])
except:
    pass
" 2>/dev/null
