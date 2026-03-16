#!/bin/bash
# self-correct.sh — When verify fails, analyze WHY and generate enriched retry prompt
# Usage: self-correct.sh <agent_id> <thread_id> [project_dir]
# Output: Enriched retry prompt to stdout
# Side effects: updates retry count, records lessons, tracks error patterns

set -euo pipefail

AGENT_ID="${1:?Usage: self-correct.sh <agent_id> <thread_id> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
PROJECT_DIR="${3:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SWARM_DIR/core/tasks"
META_FILE="$TASKS_DIR/${AGENT_ID}-${THREAD_ID}.json"
VERIFY_LOG="/tmp/verify-${AGENT_ID}-${THREAD_ID}.log"
VERIFY_RESULT="/tmp/verify-result-${AGENT_ID}-${THREAD_ID}.json"
RETRY_HISTORY="/tmp/retry-history-${AGENT_ID}-${THREAD_ID}.json"

# =============================================================
# 1. Parse verification output — what exactly failed
# =============================================================
parse_failures() {
  if [ ! -f "$VERIFY_LOG" ]; then
    echo "NO_LOG"
    return
  fi
  grep "^❌ FAIL:" "$VERIFY_LOG" | sed 's/^❌ FAIL: //' 
}

FAILURES=$(parse_failures)
if [ -z "$FAILURES" ]; then
  echo "⚠️ No failures found in verify log — nothing to self-correct"
  exit 0
fi

# =============================================================
# 2. Track retry history — detect same-error loops
# =============================================================
if [ ! -f "$RETRY_HISTORY" ]; then
  echo '{"retries":[],"error_counts":{}}' > "$RETRY_HISTORY"
fi

# Add current failures to history
FAILURE_HASH=$(echo "$FAILURES" | sort | md5sum | cut -d' ' -f1)
RETRY_NUM=$(python3 -c "
import json, sys

with open('$RETRY_HISTORY') as f:
    h = json.load(f)

failures = '''$FAILURES'''.strip().split('\n')
failure_hash = '$FAILURE_HASH'

# Count this exact error pattern
h['error_counts'][failure_hash] = h['error_counts'].get(failure_hash, 0) + 1
same_error_count = h['error_counts'][failure_hash]

h['retries'].append({
    'attempt': len(h['retries']) + 1,
    'failures': failures,
    'hash': failure_hash,
    'same_error_count': same_error_count
})

with open('$RETRY_HISTORY', 'w') as f:
    json.dump(h, f, indent=2)

print(same_error_count)
" 2>/dev/null || echo "1")

TOTAL_RETRIES=$(python3 -c "
import json
with open('$RETRY_HISTORY') as f: h = json.load(f)
print(len(h['retries']))
" 2>/dev/null || echo "1")

# =============================================================
# 3. Check for escalation conditions
# =============================================================
if [ "$RETRY_NUM" -ge 3 ]; then
  echo "🚨 ESCALATE: Same error pattern repeated $RETRY_NUM times"
  echo "Error pattern: $FAILURES"
  
  # Record lesson
  bash "$SWARM_DIR/learn.sh" lesson "$AGENT_ID" critical \
    "Task $THREAD_ID failed $RETRY_NUM times with same error" \
    "Repeated failure pattern — needs human intervention or different approach" 2>/dev/null || true
  
  # Update meta
  if [ -f "$META_FILE" ]; then
    python3 -c "
import json
with open('$META_FILE') as f: m = json.load(f)
m['status'] = 'escalated'
m['escalation_reason'] = 'Same error $RETRY_NUM times'
m.setdefault('retries', 0)
m['retries'] = $TOTAL_RETRIES
with open('$META_FILE', 'w') as f: json.dump(m, f, indent=2)
" 2>/dev/null || true
  fi
  
  exit 2
fi

if [ "$TOTAL_RETRIES" -ge 5 ]; then
  echo "🚨 ESCALATE: Total retry limit (5) reached"
  bash "$SWARM_DIR/learn.sh" lesson "$AGENT_ID" critical \
    "Task $THREAD_ID exhausted 5 total retries" \
    "Too many retries — task may be too complex or poorly defined" 2>/dev/null || true
  exit 2
fi

# =============================================================
# 4. Analyze failures and determine correction strategy
# =============================================================
STRATEGY=$(python3 -c "
import json, sys

failures = '''$FAILURES'''.strip().split('\n')
retry_num = int('$RETRY_NUM')
total = int('$TOTAL_RETRIES')

strategies = []
for f in failures:
    fl = f.lower()
    if 'lint' in fl:
        strategies.append(('lint', 'Run linter BEFORE reporting done. Fix all warnings/errors.'))
    elif 'test' in fl:
        strategies.append(('test', 'Run the project test suite and ensure ALL tests pass before reporting.'))
    elif 'syntax' in fl:
        strategies.append(('syntax', 'Check syntax of every file you changed. Use node --check for JS, python3 -m py_compile for Python.'))
    elif 'git' in fl or 'no files changed' in fl:
        strategies.append(('no-change', 'You reported done but NO files were actually changed. Make sure to save/write your changes.'))
    elif 'url' in fl or 'http' in fl:
        strategies.append(('url', 'The URL is not responding correctly. Check the service is running and the correct port/path.'))
    elif 'error message' in fl or 'error' in fl:
        strategies.append(('runtime-error', 'The deployed result shows errors. Check logs, fix the root cause.'))
    elif 'contract' in fl:
        strategies.append(('contract', 'Contract verification failed. Re-read acceptance criteria carefully.'))
    elif 'empty' in fl:
        strategies.append(('empty', 'The page/response appears empty. Check rendering, data loading.'))
    else:
        strategies.append(('unknown', f'Fix: {f}'))

# On retry 2+, suggest different approach
if total >= 2:
    strategies.append(('approach', 'IMPORTANT: Previous approach failed. Try a COMPLETELY DIFFERENT method.'))

# Output as structured text
for cat, advice in strategies:
    print(f'{cat}|{advice}')
")

# =============================================================
# 5. Get previous attempts context
# =============================================================
PREV_CONTEXT=$(python3 -c "
import json
with open('$RETRY_HISTORY') as f: h = json.load(f)
for r in h['retries'][:-1]:  # exclude current
    print(f\"Attempt {r['attempt']}: Failed with: {', '.join(r['failures'][:3])}\")" 2>/dev/null || echo "")

# =============================================================
# 6. Get relevant lessons from learning system
# =============================================================
LESSONS=$(bash "$SWARM_DIR/learn.sh" inject "$AGENT_ID" 2>/dev/null | head -20 || echo "")

# =============================================================
# 7. Generate enriched retry prompt
# =============================================================
cat <<PROMPT
## 🔄 RETRY — Attempt $((TOTAL_RETRIES + 1)) (same-error: $RETRY_NUM/3)

### ❌ What Failed in Verification:
$(echo "$FAILURES" | sed 's/^/- /')

### 📋 Previous Attempts:
${PREV_CONTEXT:-"First retry"}

### 🎯 Correction Strategy — DO THESE DIFFERENTLY:
$(echo "$STRATEGY" | while IFS='|' read -r cat advice; do echo "- **[$cat]** $advice"; done)

### ⚠️ CRITICAL RULES FOR THIS RETRY:
1. Do NOT just repeat what you did before — change your approach
2. VERIFY your own work before reporting done:
   - Run tests: \`npm test\` or equivalent
   - Check syntax: \`node --check file.js\`
   - Check URLs: \`curl -I http://...\`
3. If you're stuck, explain WHY in your report instead of pretending success
4. After 3 identical failures, this task gets ESCALATED to a human

$LESSONS
PROMPT

# =============================================================
# 8. Record retry via learn.sh
# =============================================================
FAILURE_SUMMARY=$(echo "$FAILURES" | head -1 | cut -c1-100)
bash "$SWARM_DIR/learn.sh" lesson "$AGENT_ID" medium \
  "Task $THREAD_ID retry #$TOTAL_RETRIES: $FAILURE_SUMMARY" \
  "$(echo "$STRATEGY" | head -1 | cut -d'|' -f2 | cut -c1-150)" 2>/dev/null || true

# Update meta retry count
if [ -f "$META_FILE" ]; then
  python3 -c "
import json
with open('$META_FILE') as f: m = json.load(f)
m.setdefault('retries', 0)
m['retries'] = $TOTAL_RETRIES
m['last_failures'] = '''$FAILURES'''.strip().split('\n')[:5]
with open('$META_FILE', 'w') as f: json.dump(m, f, indent=2)
" 2>/dev/null || true
fi

exit 1
