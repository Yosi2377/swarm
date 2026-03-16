#!/bin/bash
# check.sh — Independent verification of agent work (ZERO LLM, pure bash)
# Usage: check.sh <check_type> <args...>
# Returns: 0=PASS, 1=FAIL (with details on stdout)
set -euo pipefail

CHECK_TYPE="${1:-}"
shift || true

case "$CHECK_TYPE" in

  http_status)
    # check.sh http_status <url> [expected_code]
    URL="$1"
    EXPECTED="${2:-200}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$URL" 2>/dev/null || echo "000")
    if [ "$CODE" = "$EXPECTED" ]; then
      echo "✅ HTTP $CODE (expected $EXPECTED) — $URL"
      exit 0
    else
      echo "❌ HTTP $CODE (expected $EXPECTED) — $URL"
      exit 1
    fi
    ;;

  screenshot)
    # check.sh screenshot <url> <output_path>
    URL="$1"
    OUTPUT="${2:-/tmp/check-screenshot.png}"
    node -e "
      const p = require('puppeteer');
      (async()=>{
        const b = await p.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
        const pg = await b.newPage();
        await pg.setViewport({width:1280,height:800});
        await pg.goto('$URL',{waitUntil:'networkidle2',timeout:30000});
        await new Promise(r=>setTimeout(r,2000));
        await pg.screenshot({path:'$OUTPUT'});
        console.log('✅ Screenshot saved: $OUTPUT');
        await b.close();
      })().catch(e=>{console.error('❌ Screenshot failed:',e.message);process.exit(1)});
    " 2>&1
    ;;

  git_changed)
    # check.sh git_changed <repo_dir> [min_files]
    REPO="$1"
    MIN="${2:-1}"
    COUNT=$(cd "$REPO" && git diff --name-only HEAD~1 2>/dev/null | wc -l)
    if [ "$COUNT" -ge "$MIN" ]; then
      echo "✅ $COUNT files changed (min: $MIN)"
      cd "$REPO" && git diff --name-only HEAD~1
      exit 0
    else
      echo "❌ $COUNT files changed (min: $MIN)"
      exit 1
    fi
    ;;

  grep_content)
    # check.sh grep_content <url> <expected_text>
    URL="$1"
    TEXT="$2"
    BODY=$(curl -s --max-time 15 "$URL" 2>/dev/null)
    if echo "$BODY" | grep -qi "$TEXT"; then
      echo "✅ Found '$TEXT' in $URL"
      exit 0
    else
      echo "❌ '$TEXT' not found in $URL"
      exit 1
    fi
    ;;

  test_run)
    # check.sh test_run <command>
    CMD="$*"
    OUTPUT=$(eval "$CMD" 2>&1) || {
      echo "❌ Tests failed:"
      echo "$OUTPUT" | tail -20
      exit 1
    }
    echo "✅ Tests passed"
    echo "$OUTPUT" | tail -5
    exit 0
    ;;

  process_running)
    # check.sh process_running <pattern>
    PATTERN="$1"
    if pgrep -f "$PATTERN" > /dev/null 2>&1; then
      echo "✅ Process running: $PATTERN"
      exit 0
    else
      echo "❌ Process not running: $PATTERN"
      exit 1
    fi
    ;;

  file_exists)
    # check.sh file_exists <path>
    FILE="$1"
    if [ -f "$FILE" ]; then
      SIZE=$(stat -c%s "$FILE" 2>/dev/null || echo 0)
      echo "✅ File exists: $FILE ($SIZE bytes)"
      exit 0
    else
      echo "❌ File not found: $FILE"
      exit 1
    fi
    ;;

  grep_content_absent)
    URL="$1"; PATTERN="$2"
    BODY=$(curl -s "$URL" 2>/dev/null)
    VISIBLE=$(echo "$BODY" | sed 's/<script[^>]*src="[^"]*"[^>]*><\/script>//g; s/<link[^>]*>//g')
    if echo "$VISIBLE" | grep -qi "$PATTERN"; then
      echo "❌ Content still present: '$PATTERN' in $URL (should be gone)"
      exit 1
    else
      echo "✅ Content absent: '$PATTERN' not in visible HTML"
      exit 0
    fi
    ;;

  no_console_errors)
    URL="$1"
    ERRORS=$(node -e "
const p=require('puppeteer');
(async()=>{
  const b=await p.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
  const g=await b.newPage();
  const e=[];
  g.on('console',m=>{if(m.type()==='error')e.push(m.text())});
  g.on('pageerror',x=>e.push(x.message));
  await g.goto('$URL',{waitUntil:'networkidle2',timeout:30000}).catch(()=>{});
  await new Promise(r=>setTimeout(r,2000));
  console.log(JSON.stringify(e));
  await b.close();
})();
" 2>/dev/null)
    COUNT=$(echo "$ERRORS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    if [ "$COUNT" = "0" ]; then
      echo "✅ No console errors on $URL"
      exit 0
    else
      echo "❌ $COUNT console errors on $URL"
      exit 1
    fi
    ;;

  *)
    echo "Usage: check.sh <http_status|screenshot|git_changed|grep_content|grep_content_absent|no_console_errors|test_run|process_running|file_exists> <args...>"
    exit 2
    ;;

esac

# --- Extended checks ---
grep_content() {
  local url="$1" pattern="$2"
  local body=$(curl -s "$url" 2>/dev/null)
  if echo "$body" | grep -qi "$pattern"; then
    echo "✅ Content found: '$pattern' in $url"
    return 0
  else
    echo "❌ Content NOT found: '$pattern' in $url"
    return 1
  fi
}

grep_content_absent() {
  local url="$1" pattern="$2"
  local body=$(curl -s "$url" 2>/dev/null)
  # Exclude chunk/asset filenames (turbopack generates these from folder names)
  local visible=$(echo "$body" | sed 's/<script[^>]*>[^<]*<\/script>//g; s/<link[^>]*>//g')
  if echo "$visible" | grep -qi "$pattern"; then
    echo "❌ Content still present: '$pattern' in $url (should be gone)"
    return 1
  else
    echo "✅ Content absent: '$pattern' not in visible HTML of $url"
    return 0
  fi
}

no_console_errors() {
  local url="$1"
  local errors=$(node -e "
const p=require('puppeteer');
(async()=>{
  const b=await p.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
  const g=await b.newPage();
  const errs=[];
  g.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
  g.on('pageerror',e=>errs.push(e.message));
  await g.goto('$url',{waitUntil:'networkidle2',timeout:30000}).catch(()=>{});
  await new Promise(r=>setTimeout(r,2000));
  console.log(JSON.stringify(errs));
  await b.close();
})();
" 2>/dev/null)
  local count=$(echo "$errors" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
  if [ "$count" = "0" ]; then
    echo "✅ No console errors on $url"
    return 0
  else
    echo "❌ $count console errors on $url: $errors"
    return 1
  fi
}

# Dispatch to extended checks
case "${1:-}" in
  grep_content) shift; grep_content "$@" ;;
  grep_content_absent) shift; grep_content_absent "$@" ;;
  no_console_errors) shift; no_console_errors "$@" ;;
esac
