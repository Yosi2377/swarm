#!/bin/bash
# learn.sh — Learning system CLI
# Usage:
#   learn.sh lesson <agent> <severity> <what_happened> <lesson_learned>
#   learn.sh score <agent> <success|fail> [task_description]
#   learn.sh query <keyword>                    — find relevant lessons
#   learn.sh report                             — show all agent scores
#   learn.sh evolve                             — scan patterns, generate skills

DIR="$(cd "$(dirname "$0")" && pwd)/learning"
LESSONS="$DIR/lessons.json"
SCORES="$DIR/scores.json"
PATTERNS="$DIR/patterns.json"
SKILLS_DIR="$(cd "$(dirname "$0")" && pwd)/skills"

case "$1" in

# ===== LESSON =====
lesson)
  AGENT="$2"
  SEVERITY="$3"  # critical, medium, low
  WHAT="$4"
  LEARNED="$5"
  
  if [ -z "$LEARNED" ]; then
    echo "Usage: learn.sh lesson <agent> <critical|medium|low> <what_happened> <lesson_learned>"
    exit 1
  fi
  
  IMPACT=$(case "$SEVERITY" in critical) echo "1.0";; medium) echo "0.7";; *) echo "0.3";; esac)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  ID=$(date +%s%N | md5sum | head -c 8)
  
  # Add to lessons.json
  python3 -c "
import json
with open('$LESSONS') as f: data = json.load(f)
data['lessons'].append({
    'id': '$ID',
    'agent': '$AGENT',
    'severity': '$SEVERITY',
    'impact': $IMPACT,
    'what': '''$WHAT''',
    'lesson': '''$LEARNED''',
    'timestamp': '$TIMESTAMP',
    'applied': 0
})
with open('$LESSONS', 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
print('✅ Lesson saved: $ID (impact: $IMPACT)')
"
  ;;

# ===== SCORE =====
score)
  AGENT="$2"
  RESULT="$3"  # success or fail
  DESC="${4:-unnamed task}"
  
  if [ -z "$RESULT" ]; then
    echo "Usage: learn.sh score <agent> <success|fail> [description]"
    exit 1
  fi
  
  python3 -c "
import json
with open('$SCORES') as f: data = json.load(f)
a = data['agents'].get('$AGENT', {'tasks':0,'success':0,'fail':0,'score':100,'streak':0})
a['tasks'] += 1
if '$RESULT' == 'success':
    a['success'] += 1
    a['streak'] = max(0, a['streak']) + 1
else:
    a['fail'] += 1
    a['streak'] = min(0, a['streak']) - 1
# Score = success rate * 100, min 0
a['score'] = round(a['success'] / a['tasks'] * 100) if a['tasks'] > 0 else 100
data['agents']['$AGENT'] = a
with open('$SCORES', 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)

emoji = '✅' if '$RESULT' == 'success' else '❌'
status = '⚠️ LOW SCORE' if a['score'] < 30 else ''
print(f\"{emoji} $AGENT: $RESULT ($DESC) → Score: {a['score']}% {status}\")
if a['streak'] <= -3:
    print(f'🚨 $AGENT has {abs(a[\"streak\"])} consecutive failures! Consider reassigning.')
"
  ;;

# ===== QUALITY SCORE =====
quality)
  AGENT="$2"
  SCORE="$3"     # 1-10
  TASK_ID="$4"
  NOTES="${5:-}"
  
  if [ -z "$SCORE" ] || [ -z "$TASK_ID" ]; then
    echo "Usage: learn.sh quality <agent> <1-10> <task_id> [notes]"
    exit 1
  fi
  
  python3 -c "
import json, os

QUALITY_FILE = '$DIR/quality.json'
if not os.path.exists(QUALITY_FILE):
    data = {'reviews': [], 'agentAverages': {}}
else:
    with open(QUALITY_FILE) as f: data = json.load(f)

from datetime import datetime
data['reviews'].append({
    'agent': '$AGENT',
    'score': int('$SCORE'),
    'taskId': '$TASK_ID',
    'notes': '''$NOTES''',
    'timestamp': datetime.utcnow().isoformat() + 'Z'
})

# Recalc averages
from collections import defaultdict
scores = defaultdict(list)
for r in data['reviews']:
    scores[r['agent']].append(r['score'])
data['agentAverages'] = {a: round(sum(s)/len(s), 1) for a, s in scores.items()}

with open(QUALITY_FILE, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)

avg = data['agentAverages'].get('$AGENT', 0)
stars = '⭐' * int('$SCORE') + '☆' * (10 - int('$SCORE'))
print(f'{stars} $AGENT: quality $SCORE/10 (avg: {avg}/10)')
if avg < 4: print('⚠️ Low quality average! Consider training or reassignment.')
"
  ;;

# ===== QUERY =====
query)
  KEYWORD="$2"
  if [ -z "$KEYWORD" ]; then
    echo "Usage: learn.sh query <keyword>"
    exit 1
  fi
  
  python3 -c "
import json
with open('$LESSONS') as f: data = json.load(f)
matches = [l for l in data['lessons'] if '$KEYWORD'.lower() in l['what'].lower() or '$KEYWORD'.lower() in l['lesson'].lower()]
if not matches:
    print('No lessons found for: $KEYWORD')
else:
    print(f'📚 {len(matches)} lessons found for \"$KEYWORD\":')
    for l in sorted(matches, key=lambda x: x['impact'], reverse=True):
        sev = {'critical':'🔴','medium':'🟡','low':'🟢'}.get(l['severity'],'⚪')
        print(f\"  {sev} [{l['agent']}] {l['lesson']}\")
        l['applied'] += 1
    with open('$LESSONS', 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
"
  ;;

# ===== REPORT =====
report)
  python3 -c "
import json
with open('$SCORES') as f: data = json.load(f)
with open('$LESSONS') as f: ldata = json.load(f)
print('📊 Agent Intelligence Report')
print('=' * 50)
for name, a in sorted(data['agents'].items(), key=lambda x: x[1]['score'], reverse=True):
    bar = '█' * (a['score'] // 10) + '░' * (10 - a['score'] // 10)
    streak_icon = '🔥' if a['streak'] >= 3 else '💀' if a['streak'] <= -3 else ''
    status = '🟢' if a['score'] >= 70 else '🟡' if a['score'] >= 30 else '🔴'
    print(f\"  {status} {name:12s} [{bar}] {a['score']:3d}% | {a['tasks']} tasks ({a['success']}✓ {a['fail']}✗) {streak_icon}\")
print()
print(f'📚 Total lessons: {len(ldata[\"lessons\"])}')
critical = len([l for l in ldata['lessons'] if l['severity'] == 'critical'])
if critical: print(f'🔴 Critical lessons: {critical}')
"
  ;;

# ===== EVOLVE =====
evolve)
  python3 -c "
import json, os, hashlib
from collections import Counter

with open('$LESSONS') as f: ldata = json.load(f)
with open('$PATTERNS') as f: pdata = json.load(f)

# Extract patterns from lessons
words = Counter()
for l in ldata['lessons']:
    for w in l['lesson'].lower().split():
        if len(w) > 4: words[w] += 1

# Find repeated patterns (5+ occurrences)
repeated = {w: c for w, c in words.items() if c >= 5}

new_skills = 0
if repeated:
    print(f'🔍 Found {len(repeated)} repeated patterns')
    
    # Group lessons by common themes
    themes = {}
    for l in ldata['lessons']:
        for w in repeated:
            if w in l['lesson'].lower():
                themes.setdefault(w, []).append(l)
    
    for theme, lessons in themes.items():
        if len(lessons) >= 3:
            skill_id = hashlib.md5(theme.encode()).hexdigest()[:8]
            
            # Check if already generated
            if skill_id in [s['id'] for s in pdata['generatedSkills']]:
                continue
            
            # Generate skill content
            lesson_texts = '\n'.join([f'- {l[\"lesson\"]}' for l in lessons[:5]])
            skill_content = f'# Auto-Generated Skill: {theme}\n'
            skill_content += f'# Generated from {len(lessons)} lessons\n'
            skill_content += f'# Pattern detected: \"{theme}\" appeared {repeated[theme]} times\n\n'
            skill_content += f'## Lessons Learned\n{lesson_texts}\n\n'
            skill_content += f'## Rules\nWhen encountering situations related to \"{theme}\":\n'
            for l in lessons[:5]:
                skill_content += f'- {l[\"lesson\"]}\n'
            
            # Save skill
            skill_path = os.path.join('$SKILLS_DIR', f'auto-{skill_id}.md')
            with open(skill_path, 'w') as f: f.write(skill_content)
            
            pdata['generatedSkills'].append({
                'id': skill_id,
                'theme': theme,
                'lessonCount': len(lessons),
                'path': skill_path
            })
            new_skills += 1
            print(f'  🧠 Generated skill: auto-{skill_id}.md (theme: {theme}, {len(lessons)} lessons)')
    
    with open('$PATTERNS', 'w') as f: json.dump(pdata, f, indent=2, ensure_ascii=False)

if new_skills == 0:
    print('🔍 No new patterns detected (need 3+ lessons with 5+ repeated keywords)')
    print(f'   Current: {len(ldata[\"lessons\"])} lessons stored')
else:
    print(f'✅ Generated {new_skills} new skills!')
"
  ;;

*)
  echo "🧠 Learning System"
  echo "Usage:"
  echo "  learn.sh lesson <agent> <severity> <what> <lesson>  — Save a lesson"
  echo "  learn.sh score <agent> <success|fail> [desc]        — Update agent score"
  echo "  learn.sh query <keyword>                            — Find relevant lessons"
  echo "  learn.sh report                                     — Agent scores report"
  echo "  learn.sh evolve                                     — Auto-generate skills from patterns"
  ;;
esac
