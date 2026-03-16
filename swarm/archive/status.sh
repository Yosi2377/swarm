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

echo ""
echo "💰 Token Usage (last 60 min):"
python3 - 60 << 'PYEOF2'
import json, glob, os, time, sys

sessions_dir = "/root/.openclaw/agents/main/sessions"
minutes = int(sys.argv[1]) if len(sys.argv) > 1 else 60
cutoff = time.time() * 1000 - (minutes * 60 * 1000)

sessions = {}
try:
    with open(os.path.join(sessions_dir, "sessions.json")) as f:
        sessions = json.load(f)
except: pass

total_in = 0
total_out = 0
total_cost = 0

for key, val in sessions.items():
    if 'subagent' not in key or val.get('updatedAt', 0) < cutoff:
        continue
    sid = val.get('sessionId', '')
    for f in glob.glob(os.path.join(sessions_dir, f"{sid}*.jsonl")):
        try:
            with open(f) as fh:
                for line in fh:
                    try:
                        msg = json.loads(line).get('message', {})
                        u = msg.get('usage', {})
                        if u:
                            total_in += u.get('input', 0)
                            total_out += u.get('output', 0)
                    except: pass
        except: pass

if total_in or total_out:
    cost = (total_in * 3 + total_out * 15) / 1_000_000
    print(f"  In: {total_in:,} | Out: {total_out:,} | Est: ${cost:.3f}")
else:
    print("  (no recent data)")
PYEOF2
