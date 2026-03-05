#!/bin/bash
# status.sh — Quick dashboard of all agent activity
# Usage: bash status.sh [minutes]

MINUTES="${1:-30}"
REPORT_DIR="/tmp/agent-reports"
RETRY_DIR="/tmp"

echo "╔══════════════════════════════════════════════════╗"
echo "║          🐝 SWARM STATUS DASHBOARD               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Active sub-agents
echo "📡 Active Sub-Agents:"
python3 -c "
import json, time
with open('/root/.openclaw/agents/main/sessions/sessions.json') as f:
    data = json.load(f)
now = time.time() * 1000
found = False
for key, val in sorted(data.items(), key=lambda x: x[1].get('updatedAt',0), reverse=True):
    if 'subagent' in key:
        age = (now - val.get('updatedAt', 0)) / 60000
        if age < ${MINUTES}:
            status = '🟢' if age < 2 else '🟡' if age < 5 else '⚪'
            label = val.get('label', key.split(':')[-1][:25])
            print(f'  {status} {label} ({age:.0f}m ago)')
            found = True
if not found:
    print('  (none)')
" 2>/dev/null
echo ""

# Smart-eval monitors
echo "🔍 Active Monitors:"
MONITORS=$(ps aux | grep "smart-eval.sh" | grep -v grep | wc -l)
if [ "$MONITORS" -gt 0 ]; then
  ps aux | grep "smart-eval.sh" | grep -v grep | awk '{print "  🔄 PID " $2 " — " $NF}'
else
  echo "  (none)"
fi
echo ""

# Recent reports
echo "📊 Recent Reports:"
if ls "${REPORT_DIR}"/*.json 1>/dev/null 2>&1; then
  for f in "${REPORT_DIR}"/*.json; do
    python3 -c "
import json, os
with open('${f}') as fh:
    d = json.load(fh)
status = d.get('status', '?')
label = d.get('label', os.path.basename('${f}'))
icon = '✅' if status in ('pass','FIXED_AND_PASSING') else '❌' if status == 'fail' else '⚠️'
tests = d.get('tests', d.get('testsRun', '?'))
if isinstance(tests, dict):
    tests = f\"{tests.get('passed','?')}/{tests.get('total','?')}\"
print(f'  {icon} {label}: {status} (tests: {tests})')
" 2>/dev/null
  done
else
  echo "  (none)"
fi
echo ""

# Pending retries
echo "🔄 Pending Retries:"
RETRIES=$(ls /tmp/retry-request-*.json 2>/dev/null | wc -l)
if [ "$RETRIES" -gt 0 ]; then
  for f in /tmp/retry-request-*.json; do
    python3 -c "
import json
with open('${f}') as fh:
    d = json.load(fh)
print(f\"  ⚠️ {d.get('label','?')} — retry {d.get('retry','?')}: {d.get('issues','?')[:60]}\")
" 2>/dev/null
  done
else
  echo "  (none)"
fi
echo ""

# Today's log activity
LOGFILE="/root/.openclaw/workspace/swarm/logs/$(date +%Y-%m-%d).jsonl"
if [ -f "$LOGFILE" ]; then
  MSGS=$(wc -l < "$LOGFILE")
  echo "📝 Today's log: ${MSGS} messages"
else
  echo "📝 Today's log: (no log)"
fi
