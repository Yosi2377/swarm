#!/bin/bash
# scan-bugs.sh — Proactive bug scanner
# Scans code + logs, creates tasks for found issues
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISSUES=()
TASK_BASE=$((RANDOM % 9000 + 1000))

# 1. Console errors in frontend (puppeteer)
CHROME="/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome"
JS_ERRORS=$(node -e "
const p=require('puppeteer');(async()=>{
  const b=await p.launch({headless:true,executablePath:'$CHROME',args:['--no-sandbox']});
  const pg=await b.newPage();
  const errs=[];
  pg.on('pageerror',e=>errs.push(e.message));
  pg.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
  await pg.goto('http://95.111.247.22:8089',{waitUntil:'networkidle2',timeout:15000}).catch(()=>{});
  // Login
  try{const btn=await pg.\$('.auth-btn');if(btn){await pg.type('input[type=\"text\"]','admin');await pg.type('input[type=\"password\"]','admin123');await btn.click();await new Promise(r=>setTimeout(r,3000));}}catch(e){}
  await new Promise(r=>setTimeout(r,5000));
  console.log(JSON.stringify(errs));
  await b.close();
})().catch(()=>console.log('[]'));
" 2>/dev/null)

ERR_COUNT=$(echo "$JS_ERRORS" | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
if [ "$ERR_COUNT" -gt 0 ]; then
  SAMPLE=$(echo "$JS_ERRORS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d[0][:100])" 2>/dev/null)
  ISSUES+=("JS_ERROR|$ERR_COUNT JS console errors: $SAMPLE")
fi

# 2. Dead links / 404s in HTML
for PAGE in index.html admin.html agent.html; do
  FILE="/root/BettingPlatform/backend/public/$PAGE"
  [ -f "$FILE" ] || continue
  HREFS=$(grep -oP 'href="(/[^"]*)"' "$FILE" | grep -oP '"/[^"]*"' | tr -d '"')
  for HREF in $HREFS; do
    HTTP=$(curl -s -o /dev/null -w '%{http_code}' "http://95.111.247.22:8089${HREF}" 2>/dev/null)
    if [ "$HTTP" = "404" ]; then
      ISSUES+=("DEAD_LINK|404 in $PAGE: $HREF")
    fi
  done
done

# 3. Undefined variables in JS (basic grep)
for FILE in /root/BettingPlatform/backend/public/index.html; do
  UNDEFS=$(grep -n "undefined" "$FILE" 2>/dev/null | grep -v "typeof\|===\|!==\|void\|//" | head -3)
  if [ -n "$UNDEFS" ]; then
    ISSUES+=("UNDEF|Possible undefined references in $(basename $FILE)")
  fi
done

# 4. Backend error patterns
BACKEND_WARNS=$(journalctl -u betting-backend --since '1 hour ago' --no-pager -q 2>/dev/null | grep -ci 'deprecat\|warn\|unhandled' || echo 0)
if [ "$BACKEND_WARNS" -gt 10 ]; then
  SAMPLE=$(journalctl -u betting-backend --since '1 hour ago' --no-pager -q 2>/dev/null | grep -i 'deprecat\|warn\|unhandled' | tail -1 | cut -c1-100)
  ISSUES+=("BACKEND_WARN|$BACKEND_WARNS warnings: $SAMPLE")
fi

# 5. Large files that slow loading
LARGE=$(find /root/BettingPlatform/backend/public -name "*.js" -o -name "*.html" -o -name "*.css" | xargs ls -la 2>/dev/null | awk '$5>500000{print $NF": "$5" bytes"}')
if [ -n "$LARGE" ]; then
  ISSUES+=("LARGE_FILE|Large files: $LARGE")
fi

# Report
if [ ${#ISSUES[@]} -gt 0 ]; then
  MSG="🔍 Bug Scan Found ${#ISSUES[@]} issues:"
  for I in "${ISSUES[@]}"; do
    TYPE=$(echo "$I" | cut -d'|' -f1)
    DESC=$(echo "$I" | cut -d'|' -f2-)
    MSG="$MSG
  ⚠️ [$TYPE] $DESC"
  done
  "$SCRIPT_DIR/send.sh" or 1 "$MSG"
  
  # Auto-create delegation for fixable issues
  for I in "${ISSUES[@]}"; do
    TYPE=$(echo "$I" | cut -d'|' -f1)
    DESC=$(echo "$I" | cut -d'|' -f2-)
    if [ "$TYPE" = "JS_ERROR" ] || [ "$TYPE" = "DEAD_LINK" ]; then
      "$SCRIPT_DIR/delegate.sh" or koder "Auto-fix: $DESC" 2>/dev/null
    fi
  done
  echo "$MSG"
else
  echo "✅ No bugs found"
fi
