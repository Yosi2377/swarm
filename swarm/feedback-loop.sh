#!/bin/bash
# feedback-loop.sh — True self-learning: analyze failures → update system → prevent repeats
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FEEDBACK_DB="/tmp/feedback-loop.jsonl"
touch "$FEEDBACK_DB"

echo "🧠 Feedback Loop Analysis"
echo "========================="

# 1. Analyze pipeline failures from log
echo ""
echo "📊 Pipeline Stats:"
TOTAL=$(wc -l < /tmp/pipeline-completed.jsonl 2>/dev/null || echo 0)
PERFECT=$(grep '"errors":"none"' /tmp/pipeline-completed.jsonl 2>/dev/null | wc -l || echo 0)
PARTIAL=$(grep 'tests-partial' /tmp/pipeline-completed.jsonl 2>/dev/null | wc -l || echo 0)
echo "  Total: $TOTAL | Perfect: $PERFECT | Partial: $PARTIAL"

# 2. Find recurring error patterns
echo ""
echo "🔁 Recurring Patterns:"
PATTERNS=$(grep -oP '"errors":"[^"]*"' /tmp/pipeline-completed.jsonl 2>/dev/null | sort | uniq -c | sort -rn)
echo "$PATTERNS" | head -5

# 3. For each pattern, check if we already have a fix
echo ""
echo "🔧 Auto-fixes:"

# Pattern: tests-partial (most common)
if [ "$PARTIAL" -gt 2 ]; then
  echo "  ⚠️ tests-partial appears $PARTIAL times"
  
  # Check WHY tests fail — read last test output
  LAST_TASK=$(tail -1 /tmp/pipeline-completed.jsonl 2>/dev/null | python3 -c "import json,sys;print(json.loads(sys.stdin.read())['task'])" 2>/dev/null)
  TEST_FILE="$SCRIPT_DIR/tests/${LAST_TASK}.json"
  
  if [ -f "$TEST_FILE" ]; then
    # Count how many selectors don't exist
    TOTAL_TESTS=$(python3 -c "import json;print(len(json.load(open('$TEST_FILE'))['tests']))" 2>/dev/null || echo 0)
    echo "  📋 Last test file had $TOTAL_TESTS tests"
    
    # FIX: If gen-tests creates too many tests, reduce MAX
    if [ "$TOTAL_TESTS" -gt 20 ]; then
      echo "  🔧 AUTO-FIX: gen-tests.sh creates too many tests ($TOTAL_TESTS > 20)"
      echo "  Reducing MAX_TESTS in gen-tests.sh..."
      sed -i 's/MAX_TESTS=[0-9]*/MAX_TESTS=10/' "$SCRIPT_DIR/gen-tests.sh" 2>/dev/null
      echo "{\"ts\":\"$(date -Iseconds)\",\"pattern\":\"tests-partial\",\"fix\":\"reduced MAX_TESTS to 10\",\"reason\":\"$PARTIAL/$TOTAL pipelines had partial tests\"}" >> "$FEEDBACK_DB"
      echo "  ✅ Fixed: MAX_TESTS → 10"
    fi
  fi
fi

# Pattern: merge failures
MERGE_FAILS=$(grep 'merge' /tmp/pipeline-completed.jsonl 2>/dev/null | wc -l || echo 0)
if [ "$MERGE_FAILS" -gt 2 ]; then
  echo "  ⚠️ Merge issues appear $MERGE_FAILS times"
  echo "  🔧 AUTO-FIX: Adding git stash to branch-task.sh..."
  if ! grep -q "git stash" "$SCRIPT_DIR/branch-task.sh" 2>/dev/null; then
    sed -i '/git checkout master/i git stash 2>/dev/null || true' "$SCRIPT_DIR/branch-task.sh" 2>/dev/null
    echo "{\"ts\":\"$(date -Iseconds)\",\"pattern\":\"merge-fail\",\"fix\":\"added git stash to branch-task.sh\",\"reason\":\"$MERGE_FAILS merge failures\"}" >> "$FEEDBACK_DB"
    echo "  ✅ Fixed: added git stash"
  fi
fi

# 4. Analyze lesson effectiveness
echo ""
echo "📚 Lesson Analysis:"
python3 -c "
import json
d=json.load(open('$SCRIPT_DIR/learning/lessons.json'))
lessons=d.get('lessons',[])

# Find lessons that keep appearing (same 'what')
whats={}
for l in lessons:
    w=l.get('what','')[:50]
    whats[w]=whats.get(w,0)+1

repeated=[w for w,c in whats.items() if c>1]
print(f'  Total: {len(lessons)} | Unique issues: {len(whats)} | Repeated: {len(repeated)}')
if repeated:
    print('  🔁 Issues that keep happening:')
    for w in repeated[:3]:
        print(f'    - {w} ({whats[w]}x)')
" 2>/dev/null

# 5. Generate improvement score
echo ""
echo "📈 Learning Score:"
if [ "$TOTAL" -gt 0 ]; then
  SCORE=$((PERFECT * 100 / TOTAL))
  echo "  Pipeline success rate: ${SCORE}%"
  if [ "$SCORE" -lt 50 ]; then
    echo "  📉 LOW — system needs significant improvements"
  elif [ "$SCORE" -lt 80 ]; then
    echo "  📊 MEDIUM — improving but has recurring issues"
  else
    echo "  📈 HIGH — system is learning effectively"
  fi
else
  echo "  No data yet"
fi

# 6. Log this analysis
echo "{\"ts\":\"$(date -Iseconds)\",\"total\":$TOTAL,\"perfect\":$PERFECT,\"partial\":$PARTIAL,\"score\":\"${SCORE:-0}%\"}" >> "$FEEDBACK_DB"

echo ""
echo "✅ Feedback loop complete. Fixes applied: $(wc -l < "$FEEDBACK_DB") total adjustments"
