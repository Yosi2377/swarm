#!/bin/bash
# watch-task.sh — מעקב אוטומטי אחרי סוכן + דיווח ליוסי
# Usage: watch-task.sh <label> <thread_id> <project> [description]
# Runs in background. Polls sub-agent. Reports every step to General.

LABEL="$1"
THREAD="$2"
PROJECT="$3"
DESC="${4:-task}"
SEND="/root/.openclaw/workspace/swarm/send.sh"
SANDBOX_URL="http://95.111.247.22:9089"
BROWSER_TEST="/root/.openclaw/workspace/swarm/browser-test.sh"
CHECK_INTERVAL=15  # seconds between checks
MAX_WAIT=300       # 5 minutes max

elapsed=0

# Step 1: Report started
$SEND or 1 "⏳ #${THREAD} — סוכן עובד על: ${DESC}"

# Step 2: Poll until sub-agent finishes
while [ $elapsed -lt $MAX_WAIT ]; do
  sleep $CHECK_INTERVAL
  elapsed=$((elapsed + CHECK_INTERVAL))
  
  # Check if sub-agent finished (look for commit in sandbox)
  if [ -d "/root/sandbox/${PROJECT}" ]; then
    LAST_COMMIT_AGE=$(cd "/root/sandbox/${PROJECT}" && git log -1 --format="%cr" 2>/dev/null)
    LAST_COMMIT_SEC=$(cd "/root/sandbox/${PROJECT}" && echo $(( $(date +%s) - $(git log -1 --format="%ct" 2>/dev/null || echo 0) )))
    
    if [ "$LAST_COMMIT_SEC" -lt 60 ] 2>/dev/null; then
      # Fresh commit detected
      $SEND or 1 "✅ #${THREAD} — סוכן סיים (commit ${LAST_COMMIT_AGE}). בודק + צילום מסך..."
      
      # Step 3: Take screenshot
      systemctl restart sandbox-betting-backend 2>/dev/null
      sleep 3
      $BROWSER_TEST screenshot "$SANDBOX_URL" "/tmp/watch-${THREAD}.png" 1400 900 2>/dev/null
      
      if [ -f "/tmp/watch-${THREAD}.png" ]; then
        # Send screenshot to General
        TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token)
        curl -s -F "chat_id=-1003815143703" -F "message_thread_id=1" \
          -F "photo=@/tmp/watch-${THREAD}.png" \
          -F "caption=📸 SANDBOX #${THREAD} — ${DESC}

מאשר לפרודקשן?" \
          "https://api.telegram.org/bot${TOKEN}/sendPhoto" >/dev/null 2>&1
        
        $SEND or 1 "📸 #${THREAD} — screenshot נשלח. ממתין לאישור יוסי."
      else
        $SEND or 1 "⚠️ #${THREAD} — סוכן סיים אבל screenshot נכשל. בודק ידנית..."
      fi
      
      exit 0
    fi
  fi
  
  # Every 60 seconds, send progress update
  if [ $((elapsed % 60)) -eq 0 ]; then
    $SEND or 1 "⏳ #${THREAD} — עדיין עובד... (${elapsed}s)"
  fi
done

# Timeout
$SEND or 1 "⚠️ #${THREAD} — timeout אחרי ${MAX_WAIT}s. צריך בדיקה."
exit 1
