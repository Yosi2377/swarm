#!/bin/bash
# evolve.sh — Analyze agent performance and suggest improvements
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🧬 Evolution Analysis"
echo "====================="

# 1. Analyze pipeline success rate
TOTAL=$(wc -l < /tmp/pipeline-completed.jsonl 2>/dev/null || echo 0)
PERFECT=$(grep '"errors":"none"' /tmp/pipeline-completed.jsonl 2>/dev/null | wc -l || echo 0)
if [ "$TOTAL" -gt 0 ]; then
  RATE=$((PERFECT * 100 / TOTAL))
  echo "📊 Pipeline success: $PERFECT/$TOTAL ($RATE%)"
  if [ "$RATE" -lt 80 ]; then
    echo "  ⚠️ Low success rate — checking common errors..."
    grep -oP '"errors":"[^"]*"' /tmp/pipeline-completed.jsonl | sort | uniq -c | sort -rn | head -3
  fi
else
  echo "📊 No pipeline data yet"
fi

# 2. Analyze common lessons (what keeps going wrong)
echo ""
echo "🔴 Top recurring issues:"
python3 -c "
import json
d=json.load(open('$SCRIPT_DIR/learning/lessons.json'))
lessons=d.get('lessons',[])
critical=[l for l in lessons if l.get('severity')=='critical']
by_agent={}
for l in lessons:
    a=l.get('agent','?')
    by_agent[a]=by_agent.get(a,0)+1
print(f'  Total lessons: {len(lessons)}')
print(f'  Critical: {len(critical)}')
for a,c in sorted(by_agent.items(),key=lambda x:-x[1])[:5]:
    print(f'  {a}: {c} lessons')
" 2>/dev/null

# 3. Analyze task duration (from pipeline log)
echo ""
echo "⏱️ Task performance:"
python3 -c "
import json
lines=open('/tmp/pipeline-completed.jsonl').readlines()
for line in lines[-5:]:
    d=json.loads(line)
    print(f'  Task {d[\"task\"]} ({d[\"agent\"]}): {d[\"pass\"]}/{d[\"total\"]} — errors: {d[\"errors\"]}')
" 2>/dev/null

# 4. Auto-improve: update SYSTEM.md with new rules based on failures
echo ""
echo "🧬 Improvements:"
if grep -q "tests-partial" /tmp/pipeline-completed.jsonl 2>/dev/null; then
  echo "  💡 tests-partial is common → gen-tests.sh may need better selector filtering"
fi
if grep -q "merge" /tmp/pipeline-completed.jsonl 2>/dev/null; then
  echo "  💡 merge issues found → branch-task.sh may need git stash before branch"
fi

# 5. Score improvement suggestions
echo ""
echo "📈 Recommendations:"
echo "  1. Add retry logic to pipeline steps that fail intermittently"
echo "  2. Improve gen-tests.sh to test only visible elements"
echo "  3. Add post-deploy smoke test to handle-approve.sh"
echo "  4. Track avg task time per agent for workload balancing"
