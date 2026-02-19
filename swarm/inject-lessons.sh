#!/bin/bash
# inject-lessons.sh — Query relevant lessons for a task and output them
# Usage: inject-lessons.sh "task description keywords"
# Output: formatted lessons text to inject into agent prompt

DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS="$DIR/learning/lessons.json"
QUERY="$1"

if [ -z "$QUERY" ]; then
  echo "Usage: inject-lessons.sh <keywords>"
  exit 1
fi

python3 - "$LESSONS" "$QUERY" <<'PYEOF'
import json, sys, re, math
from collections import Counter

lessons_path = sys.argv[1]
query = sys.argv[2].lower()

with open(lessons_path) as f:
    lessons = json.load(f).get("lessons", [])

query_words = set(re.findall(r'\w+', query))
query_words -= {"the", "a", "an", "is", "are", "was", "were", "to", "for", "in", "on", "at", "of", "and", "or"}

def score_lesson(lesson):
    text = f"{lesson.get('what', '')} {lesson.get('lesson', '')}".lower()
    text_words = set(re.findall(r'\w+', text))
    
    # Word overlap
    overlap = len(query_words & text_words)
    if overlap == 0:
        return 0
    
    # Severity boost
    sev = lesson.get("severity", "low")
    boost = {"critical": 3, "high": 2, "medium": 1.5}.get(sev, 1)
    
    # Recency boost (newer = better)
    applied = lesson.get("applied", 0)
    recency = 1.0 / (1 + applied * 0.1)
    
    return overlap * boost * recency

scored = [(score_lesson(l), l) for l in lessons]
scored = [(s, l) for s, l in scored if s > 0]
scored.sort(key=lambda x: -x[0])

# Top 5 relevant lessons
top = scored[:5]
if not top:
    print("(אין לקחים רלוונטיים)")
    sys.exit(0)

print("📚 לקחים רלוונטיים מנסיון קודם:")
for score, l in top:
    severity_emoji = {"critical": "🔴", "high": "🟠", "medium": "🟡"}.get(l.get("severity", ""), "⚪")
    print(f"{severity_emoji} {l['what']}: {l['lesson']}")
PYEOF
