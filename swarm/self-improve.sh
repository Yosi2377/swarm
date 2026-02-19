#!/bin/bash
# self-improve.sh — Level 8 self-improvement (BASH, no tokens!)
# Runs via cron 1-2x/day. Only wakes agent when action needed.
# Usage: self-improve.sh [check|fix|report]

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
LEARNING="$DIR/learning"
LESSONS="$LEARNING/lessons.json"
SCORES="$LEARNING/scores.json"
REPORT="/tmp/self-improve-report.json"
ALERT="/tmp/self-improve-alert.txt"

# Clean previous
rm -f "$ALERT" "$REPORT"

ISSUES=0
ALERTS=""

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# ============================================
# CHECK 1: Pattern Detection — repeated failures
# ============================================
check_patterns() {
  log "🔍 Checking failure patterns..."
  
  python3 - "$LESSONS" "$SCORES" <<'PYEOF'
import json, sys, collections

lessons_path, scores_path = sys.argv[1], sys.argv[2]

with open(lessons_path) as f:
    lessons = json.load(f).get("lessons", [])
with open(scores_path) as f:
    scores = json.load(f)

# Find repeated failure topics (3+ similar lessons)
fail_keywords = collections.Counter()
for l in lessons:
    if l.get("severity") in ("critical", "high") or "fail" in l.get("what", "").lower():
        # Extract key words
        words = set(l.get("what", "").lower().split() + l.get("lesson", "").lower().split())
        for w in words:
            if len(w) > 4 and w not in ("agent", "koder", "error", "failed", "should", "always", "never"):
                fail_keywords[w] += 1

# Topics that appear 3+ times = pattern
patterns = {k: v for k, v in fail_keywords.items() if v >= 3}
if patterns:
    top = sorted(patterns.items(), key=lambda x: -x[1])[:5]
    print("PATTERNS_FOUND")
    for word, count in top:
        print(f"  {word}: {count} occurrences")
else:
    print("NO_PATTERNS")

# Check agent health
agents = scores.get("agents", {})
for name, data in agents.items():
    score = data.get("score", 50)
    streak = data.get("streak", 0)
    if score < 40:
        print(f"LOW_SCORE:{name}:{score}")
    if streak <= -5:
        print(f"BAD_STREAK:{name}:{streak}")
PYEOF
}

# ============================================
# CHECK 2: Production Health (no tokens!)
# ============================================
check_production() {
  log "🏥 Checking production health..."
  
  # ZozoBet alive?
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:3001/api/events?limit=1 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" != "200" ]; then
    echo "PROD_DOWN:backend:$HTTP_CODE" >> "$ALERT"
    ISSUES=$((ISSUES + 1))
  fi
  
  # Aggregator alive?
  AGG_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:3002/api/health 2>/dev/null || echo "000")
  # Fallback: if no health endpoint, just check if process is running
  if [ "$AGG_CODE" != "200" ]; then
    if systemctl is-active --quiet betting-aggregator 2>/dev/null; then
      AGG_CODE="200(svc)"
    fi
  fi
  if [ "$AGG_CODE" != "200" ] && [ "$AGG_CODE" != "200(svc)" ]; then
    echo "PROD_DOWN:aggregator:$AGG_CODE" >> "$ALERT"
    ISSUES=$((ISSUES + 1))
  fi
  
  # Services running?
  for svc in betting-backend betting-aggregator; do
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
      echo "SERVICE_DOWN:$svc" >> "$ALERT"
      ISSUES=$((ISSUES + 1))
    fi
  done
  
  # Disk space
  DISK_PCT=$(df / --output=pcent | tail -1 | tr -d ' %')
  if [ "$DISK_PCT" -gt 90 ]; then
    echo "DISK_HIGH:$DISK_PCT%" >> "$ALERT"
    ISSUES=$((ISSUES + 1))
  fi
  
  # MongoDB alive?
  if ! mongosh --eval "db.stats()" --quiet blackjack >/dev/null 2>&1; then
    echo "MONGO_DOWN" >> "$ALERT"
    ISSUES=$((ISSUES + 1))
  fi
  
  # Events freshness — any events updated in last 2 hours?
  FRESH=$(mongosh --eval "db.events.countDocuments({updatedAt:{\$gte:new Date(Date.now()-7200000)}})" --quiet betting 2>/dev/null || echo "0")
  if [ "$FRESH" = "0" ]; then
    echo "STALE_DATA:no events updated in 2h" >> "$ALERT"
    ISSUES=$((ISSUES + 1))
  fi
  
  log "  Backend: $HTTP_CODE | Aggregator: $AGG_CODE | Disk: ${DISK_PCT}% | Fresh events: $FRESH"
}

# ============================================
# CHECK 3: Browser Test Selectors Valid?
# ============================================
check_selectors() {
  log "🎯 Checking CSS selectors..."
  
  # Check critical classes exist in source (HTML + JS templates)
  INDEXHTML="/root/BettingPlatform/backend/public/index.html"
  if [ ! -f "$INDEXHTML" ]; then
    log "  ⚠️ index.html not found"
    return
  fi
  
  for sel in featured-match odd-btn bet-slip sidebar-left; do
    if grep -q "$sel" "$INDEXHTML"; then
      log "  ✅ .$sel found"
    else
      log "  ❌ .$sel NOT in source"
      echo "SELECTOR_MISSING:$sel" >> "$ALERT"
    fi
  done
}

# ============================================
# CHECK 4: Lesson Quality — duplicates, junk
# ============================================
check_lessons() {
  log "📚 Checking lesson quality..."
  
  python3 - "$LESSONS" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    lessons = json.load(f).get("lessons", [])

total = len(lessons)
junk = 0
dupes = 0
seen = set()

for l in lessons:
    lesson_text = l.get("lesson", "")
    what_text = l.get("what", "")
    
    # Junk: very short or just "test"
    if len(lesson_text) < 10 or lesson_text.strip() in ("test", "auto-commit חובה"):
        junk += 1
    
    # Duplicates: same lesson text
    key = lesson_text[:50].lower()
    if key in seen:
        dupes += 1
    seen.add(key)

print(f"LESSONS:{total}:JUNK:{junk}:DUPES:{dupes}")
if junk > 10:
    print(f"CLEANUP_NEEDED:junk={junk}")
if dupes > 5:
    print(f"CLEANUP_NEEDED:dupes={dupes}")
PYEOF
}

# ============================================
# CHECK 5: Sandbox in sync with production?
# ============================================
check_sandbox_sync() {
  log "🔄 Checking sandbox sync..."
  
  PROD="/root/BettingPlatform"
  SAND="/root/sandbox/BettingPlatform"
  
  if [ ! -d "$SAND" ]; then
    log "  ⚠️ No sandbox directory"
    return
  fi
  
  # Compare key files
  for f in backend/public/index.html aggregator/src/inplay-parser.js aggregator/src/index.js; do
    if [ -f "$PROD/$f" ] && [ -f "$SAND/$f" ]; then
      if ! diff -q "$PROD/$f" "$SAND/$f" >/dev/null 2>&1; then
        echo "SANDBOX_DRIFT:$f" >> "$ALERT"
        ISSUES=$((ISSUES + 1))
      fi
    fi
  done
}

# ============================================
# MAIN
# ============================================
main() {
  log "🤖 Self-Improve Check Starting..."
  
  check_patterns 2>&1
  check_production
  check_selectors
  check_lessons 2>&1
  check_sandbox_sync
  
  # Build report
  python3 -c "
import json, datetime
report = {
    'timestamp': datetime.datetime.now().isoformat(),
    'issues': $ISSUES,
    'has_alert': $( [ -f "$ALERT" ] && echo "True" || echo "False" )
}
with open('$REPORT', 'w') as f:
    json.dump(report, f, indent=2)
"
  
  if [ -f "$ALERT" ] && [ -s "$ALERT" ]; then
    log "🚨 $ISSUES issues found! Alert saved to $ALERT"
    cat "$ALERT"
    exit 1  # Non-zero = needs attention
  else
    log "✅ All clear — no issues"
    exit 0
  fi
}

main 2>&1
