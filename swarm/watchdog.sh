#!/bin/bash
# Watchdog — cron-compatible script to detect stuck agents
# Usage: watchdog.sh [max_minutes]
# Can be called every 2 minutes via cron

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
MAX_MINUTES="${1:-${WATCHDOG_MAX_MINUTES:-5}}"

export WATCHDOG_MAX_MINUTES="$MAX_MINUTES"

node -e "
  const { runWatchdog } = require('${SWARM_DIR}/core/watchdog');
  const results = runWatchdog({ maxMinutes: ${MAX_MINUTES} });
  const stuck = results.filter(r => r.action === 'flagged_stuck');
  console.log(JSON.stringify({ 
    timestamp: new Date().toISOString(),
    checked: results.length, 
    stuck: stuck.length,
    alive: results.filter(r => r.action === 'alive').length,
    results 
  }, null, 2));
  if (stuck.length > 0) process.exit(1);
" 2>/dev/null

exit $?
