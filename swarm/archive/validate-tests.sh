#!/bin/bash
# validate-tests.sh — Validates browser test selectors EXIST on page before evaluator runs
# Usage: validate-tests.sh <url> <task_file>
# Returns: 0 if all selectors valid, 1 if any missing (with fixes)
set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
URL="${1:?Usage: validate-tests.sh <url> <task_file>}"
TASK_FILE="${2:?Missing task file}"

# Extract selectors from task file Browser Tests section
SELECTORS=$(sed -n '/^## Browser Tests/,/^##/p' "$TASK_FILE" | grep -oP '(?<=: )[.#][a-zA-Z0-9_-]+(\s*,\s*[.#][a-zA-Z0-9_-]+)*' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort -u)

if [ -z "$SELECTORS" ]; then
  echo "⚠️ No selectors found in task file"
  exit 0
fi

echo "🔍 Validating selectors on $URL..."

FAILED=0
REPORT=""

for SEL in $SELECTORS; do
  FOUND=$(node -e "
    const p=require('puppeteer');
    const al=require('$SWARM_DIR/auto-login');
    (async()=>{
      const b=await p.launch({headless:true,args:['--no-sandbox']});
      const pg=await b.newPage();
      await al(pg,'$URL');
      await pg.goto('$URL',{waitUntil:'networkidle2',timeout:15000});
      await new Promise(r=>setTimeout(r,3000));
      const count=await pg.evaluate((s)=>document.querySelectorAll(s).length,'$SEL');
      console.log(count);
      await b.close();
    })().catch(()=>console.log(-1));
  " 2>/dev/null)

  if [ "$FOUND" = "0" ] || [ "$FOUND" = "-1" ]; then
    echo "  ❌ $SEL → NOT FOUND"
    # Try to find similar
    SIMILAR=$(node -e "
      const p=require('puppeteer');
      const al=require('$SWARM_DIR/auto-login');
      (async()=>{
        const b=await p.launch({headless:true,args:['--no-sandbox']});
        const pg=await b.newPage();
        await al(pg,'$URL');
        await pg.goto('$URL',{waitUntil:'networkidle2',timeout:15000});
        await new Promise(r=>setTimeout(r,3000));
        const word='$SEL'.replace(/^[.#]/,'').replace(/-/g,'.');
        const all=await pg.evaluate((w)=>{
          const classes=new Set();
          document.querySelectorAll('*').forEach(el=>{
            el.classList.forEach(c=>{if(c.toLowerCase().includes(w.toLowerCase().split('.')[0]))classes.add('.'+c)});
          });
          return [...classes].slice(0,5);
        },word);
        console.log(all.join(', ')||'(none)');
        await b.close();
      })().catch(()=>console.log('error'));
    " 2>/dev/null)
    REPORT="$REPORT\n❌ $SEL → NOT FOUND. Similar: $SIMILAR"
    FAILED=1
  else
    echo "  ✅ $SEL → $FOUND elements"
  fi
done

if [ "$FAILED" = "1" ]; then
  echo ""
  echo "⚠️ INVALID SELECTORS FOUND — fix task file before running evaluator!"
  echo -e "$REPORT"
  exit 1
fi

echo "✅ All selectors valid"
exit 0
