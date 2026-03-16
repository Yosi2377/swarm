#!/bin/bash
# cron-self-improve.sh — Called by OpenClaw cron, runs self-improve.sh
# If issues found → writes /tmp/watchdog-alert.json for heartbeat pickup
# If clean → does nothing (zero tokens!)

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/self-improve-$(date +%Y%m%d-%H%M).log"

# Run the actual checks
bash "$DIR/self-improve.sh" > "$LOG" 2>&1
RC=$?

if [ $RC -ne 0 ] && [ -f /tmp/self-improve-alert.txt ]; then
  # Create watchdog alert for heartbeat to pick up
  ALERT_TEXT=$(cat /tmp/self-improve-alert.txt)
  python3 -c "
import json
alert = {
    'source': 'self-improve',
    'issues': '''$ALERT_TEXT''',
    'log': '$LOG',
    'action': 'review and fix issues'
}
with open('/tmp/watchdog-alert.json', 'w') as f:
    json.dump(alert, f, indent=2)
print('Alert written')
"
fi
