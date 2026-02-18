#!/bin/bash
# autonomous.sh — Autonomous agent loop (SANDBOX ONLY)
# Scans for issues, fixes on sandbox, sends PR for approval
# Production deploy ONLY via human approve
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/tmp/autonomous-state.json"
MAX_FIXES_PER_RUN=2
LOCK_FILE="/tmp/autonomous.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
  if [ "$AGE" -lt 300 ]; then
    echo "🔒 Already running (${AGE}s ago). Skipping."
    exit 0
  fi
fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

echo "🤖 Autonomous Agent — $(date)"
echo "================================"
echo "⚠️ SANDBOX ONLY — production requires human approval"
echo ""

FIXES=0

# === Phase 1: Scan for issues ===
echo "🔍 Phase 1: Scanning..."

ISSUES=()

# 1a. JS Console errors
CHROME="/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome"
JS_ERRORS=$(node -e "
const p=require('puppeteer');(async()=>{
  const b=await p.launch({headless:true,executablePath:'$CHROME',args:['--no-sandbox']});
  const pg=await b.newPage();
  const errs=[];
  pg.on('pageerror',e=>errs.push(e.message));
  pg.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
  await pg.goto('http://95.111.247.22:9089',{waitUntil:'networkidle2',timeout:15000}).catch(()=>{});
  try{const btn=await pg.\$('.auth-btn');if(btn){await pg.type('input[type=\"text\"]','admin');await pg.type('input[type=\"password\"]','admin123');await btn.click();await new Promise(r=>setTimeout(r,3000));}}catch(e){}
  await new Promise(r=>setTimeout(r,5000));
  console.log(JSON.stringify(errs));
  await b.close();
})().catch(()=>console.log('[]'));
" 2>/dev/null)
ERR_COUNT=$(echo "$JS_ERRORS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(len([e for e in d if 'Cross-Origin' not in e]))" 2>/dev/null || echo 0)
if [ "$ERR_COUNT" -gt 0 ]; then
  ISSUES+=("js_errors:$ERR_COUNT JS errors (excluding CORS)")
fi

# 1b. 404 links
for PAGE in index.html admin.html agent.html; do
  FILE="/root/sandbox/BettingPlatform/backend/public/$PAGE"
  [ -f "$FILE" ] || continue
  HREFS=$(grep -oP 'href="(/[^"]*)"' "$FILE" | grep -oP '"/[^"]*"' | tr -d '"' | head -10)
  for HREF in $HREFS; do
    HTTP=$(curl -s -o /dev/null -w '%{http_code}' "http://95.111.247.22:9089${HREF}" 2>/dev/null)
    if [ "$HTTP" = "404" ]; then
      ISSUES+=("dead_link:404 $PAGE → $HREF")
    fi
  done
done

# 1c. Service health
for SVC in betting-backend betting-aggregator; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    ISSUES+=("service_down:$SVC is not running")
  fi
done

# 1d. Stale data
STALE=$(mongosh --quiet betting --eval "
const c=new Date(Date.now()-30*60*1000);
print(db.events.countDocuments({isLive:true,oddsUpdatedAt:{\$lt:c}}));
" 2>/dev/null || echo "0")
if [ "$STALE" -gt 20 ]; then
  ISSUES+=("stale_data:$STALE live events with stale odds (30+ min)")
fi

echo "Found ${#ISSUES[@]} issues"

if [ ${#ISSUES[@]} -eq 0 ]; then
  echo "✅ No issues found. All good!"
  exit 0
fi

# === Phase 2: Report issues ===
echo ""
echo "📋 Phase 2: Reporting..."
MSG="🤖 Autonomous Scan — ${#ISSUES[@]} issues found:"
for I in "${ISSUES[@]}"; do
  TYPE=$(echo "$I" | cut -d: -f1)
  DESC=$(echo "$I" | cut -d: -f2-)
  MSG="$MSG
  ⚠️ $DESC"
done
"$SCRIPT_DIR/send.sh" or 1 "$MSG" 2>/dev/null

# === Phase 3: Auto-fix on SANDBOX (up to MAX_FIXES_PER_RUN) ===
echo ""
echo "🔧 Phase 3: Auto-fixing on sandbox (max $MAX_FIXES_PER_RUN)..."

for I in "${ISSUES[@]}"; do
  [ "$FIXES" -ge "$MAX_FIXES_PER_RUN" ] && break
  
  TYPE=$(echo "$I" | cut -d: -f1)
  DESC=$(echo "$I" | cut -d: -f2-)
  
  case "$TYPE" in
    service_down)
      SVC=$(echo "$DESC" | awk '{print $1}')
      systemctl restart "$SVC" 2>/dev/null
      echo "  🔧 Restarted $SVC"
      FIXES=$((FIXES+1))
      ;;
    stale_data)
      systemctl restart betting-aggregator 2>/dev/null
      echo "  🔧 Restarted aggregator for stale data"
      FIXES=$((FIXES+1))
      ;;
    dead_link)
      # Report only — needs agent to fix
      echo "  📋 Dead link needs agent fix: $DESC"
      "$SCRIPT_DIR/delegate.sh" or koder "Fix dead link on sandbox: $DESC" 2>/dev/null
      FIXES=$((FIXES+1))
      ;;
    js_errors)
      echo "  📋 JS errors need investigation"
      ;;
  esac
done

echo ""
echo "✅ Done: $FIXES fixes applied, ${#ISSUES[@]} total issues"
