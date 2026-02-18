#!/bin/bash
# watchdog.sh — Pure bash monitoring. NO AI tokens. Runs via systemd timer.
# Only sends alerts when something is WRONG.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$SCRIPT_DIR/send.sh"
ALERT=0

# 1. Services alive?
for SVC in betting-backend betting-aggregator; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    systemctl restart "$SVC" 2>/dev/null
    sleep 3
    if systemctl is-active --quiet "$SVC"; then
      "$SEND" or 1 "⚠️ $SVC was down — auto-restarted ✅" 2>/dev/null
    else
      "$SEND" or 1 "🔴 $SVC DOWN — restart failed!" 2>/dev/null
    fi
    ALERT=1
  fi
done

# 2. HTTP check
for URL in "http://95.111.247.22:8089|Production" "http://95.111.247.22:9089|Sandbox"; do
  ADDR="${URL%%|*}"
  NAME="${URL##*|}"
  HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$ADDR" 2>/dev/null)
  if [ "$HTTP" != "200" ]; then
    "$SEND" or 1 "🔴 $NAME HTTP $HTTP (expected 200)" 2>/dev/null
    ALERT=1
  fi
done

# 3. Disk space
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$DISK_PCT" -gt 85 ]; then
  "$SEND" or 1 "⚠️ Disk ${DISK_PCT}% — cleanup needed" 2>/dev/null
  # Auto-clean
  journalctl --vacuum-time=3d 2>/dev/null
  ALERT=1
fi

# 4. MongoDB alive
if ! mongosh --quiet --eval "db.runCommand({ping:1})" betting >/dev/null 2>&1; then
  "$SEND" or 1 "🔴 MongoDB not responding!" 2>/dev/null
  ALERT=1
fi

# 5. Pipeline completions (supervisor role)
if [ -f /tmp/pipeline-completed.jsonl ] && [ -f /tmp/supervisor-reported.txt ]; then
  while IFS= read -r LINE; do
    TASK=$(echo "$LINE" | python3 -c "import json,sys;print(json.loads(sys.stdin.read())['task'])" 2>/dev/null)
    if [ -n "$TASK" ] && ! grep -q "task-$TASK" /tmp/supervisor-reported.txt 2>/dev/null; then
      DESC=$(echo "$LINE" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('desc','?'))" 2>/dev/null)
      AGENT=$(echo "$LINE" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('agent','?'))" 2>/dev/null)
      PASS=$(echo "$LINE" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('pass','?'))" 2>/dev/null)
      "$SEND" or 1 "✅ Task $TASK ($AGENT): $DESC — $PASS/8" 2>/dev/null
      echo "task-$TASK" >> /tmp/supervisor-reported.txt
    fi
  done < /tmp/pipeline-completed.jsonl
elif [ -f /tmp/pipeline-completed.jsonl ]; then
  touch /tmp/supervisor-reported.txt
fi

# 6. Stale odds (aggregator stuck)
STALE=$(mongosh --quiet betting --eval "print(db.events.countDocuments({completed:false,'scores.home':{\$ne:null},oddsUpdatedAt:{\$lt:new Date(Date.now()-30*60*1000)}}))" 2>/dev/null || echo 0)
if [ "$STALE" -gt 20 ]; then
  systemctl restart betting-aggregator 2>/dev/null
  "$SEND" or 1 "⚠️ $STALE stale events — aggregator restarted" 2>/dev/null
  ALERT=1
fi

# 7. JS errors / 404s → delegate to AI agent (only if found)
CHROME="/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome"
ERRORS=$(node -e "
const p=require('puppeteer');(async()=>{
  const b=await p.launch({headless:true,executablePath:'$CHROME',args:['--no-sandbox']});
  const pg=await b.newPage();
  const errs=[];
  pg.on('pageerror',e=>errs.push(e.message));
  await pg.goto('http://95.111.247.22:9089',{waitUntil:'networkidle2',timeout:10000}).catch(()=>{});
  await new Promise(r=>setTimeout(r,3000));
  const real=errs.filter(e=>!e.includes('Cross-Origin'));
  console.log(real.length);
  await b.close();
})().catch(()=>console.log(0));
" 2>/dev/null)

if [ "${ERRORS:-0}" -gt 0 ]; then
  # Found real JS errors → wake AI to investigate
  "$SEND" or 1 "🐛 $ERRORS JS errors found on sandbox — waking AI to fix" 2>/dev/null
  echo "{\"type\":\"js_errors\",\"count\":$ERRORS,\"ts\":\"$(date -Iseconds)\"}" > /tmp/watchdog-alert.json
  # Wake AI via OpenClaw cron wake
  curl -s -X POST "http://127.0.0.1:18789/api/cron/wake" \
    -H "Authorization: Bearer a70b2c01b30494f2a6edf62a7d86f148c8e5b5572eb838de" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"🐛 Watchdog: $ERRORS JS errors on sandbox. Read /tmp/watchdog-alert.json and spawn koder to fix.\",\"mode\":\"now\"}" 2>/dev/null
  ALERT=1
fi

# 8. 404 check on key assets
# Only check assets that are referenced in index.html
ASSETS=$(grep -oP 'href="(/[^"]*\.(?:css|js|png|ico))"' /root/BettingPlatform/backend/public/index.html 2>/dev/null | grep -oP '"/[^"]*"' | tr -d '"' | head -5)
for ASSET in $ASSETS; do
  HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://95.111.247.22:9089${ASSET}" 2>/dev/null)
  if [ "$HTTP" = "404" ]; then
    "$SEND" or 1 "🐛 404: $ASSET — waking AI to fix" 2>/dev/null
    echo "{\"type\":\"404\",\"asset\":\"$ASSET\",\"ts\":\"$(date -Iseconds)\"}" > /tmp/watchdog-alert.json
    curl -s -X POST "http://127.0.0.1:18789/api/cron/wake" \
      -H "Authorization: Bearer a70b2c01b30494f2a6edf62a7d86f148c8e5b5572eb838de" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"🐛 Watchdog: 404 on $ASSET. Read /tmp/watchdog-alert.json and spawn koder to fix on sandbox.\",\"mode\":\"now\"}" 2>/dev/null
    ALERT=1
    break  # One alert is enough
  fi
done

# Silent if no issues
exit 0
