#!/bin/bash
# detect-issues.sh — Proactive issue detection
# Run via cron every 5 minutes
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISSUES=()

# 1. Server errors in last 5 min
BACKEND_ERRORS=$(journalctl -u betting-backend --since '5 min ago' --no-pager -q 2>/dev/null | grep -ci 'error\|crash\|fatal\|ECONNREFUSED\|ENOSPC')
if [ "$BACKEND_ERRORS" -gt 0 ]; then
  SAMPLE=$(journalctl -u betting-backend --since '5 min ago' --no-pager -q 2>/dev/null | grep -i 'error\|crash\|fatal' | tail -1)
  ISSUES+=("🔴 Backend: ${BACKEND_ERRORS} errors — $SAMPLE")
fi

AGG_ERRORS=$(journalctl -u betting-aggregator --since '5 min ago' --no-pager -q 2>/dev/null | grep -ci 'error\|crash\|fatal')
if [ "$AGG_ERRORS" -gt 0 ]; then
  SAMPLE=$(journalctl -u betting-aggregator --since '5 min ago' --no-pager -q 2>/dev/null | grep -i 'error\|crash\|fatal' | tail -1)
  ISSUES+=("🔴 Aggregator: ${AGG_ERRORS} errors — $SAMPLE")
fi

# 2. Service down
for SVC in betting-backend betting-aggregator sandbox-betting-backend; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    ISSUES+=("🔴 $SVC is DOWN!")
    # Auto-fix: try restart
    systemctl restart "$SVC" 2>/dev/null
    sleep 3
    if systemctl is-active --quiet "$SVC"; then
      ISSUES+=("✅ $SVC auto-restarted successfully")
    else
      ISSUES+=("❌ $SVC restart FAILED")
    fi
  fi
done

# 3. Disk space
DISK_PCT=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$DISK_PCT" -gt 85 ]; then
  ISSUES+=("⚠️ Disk usage: ${DISK_PCT}%")
  if [ "$DISK_PCT" -gt 95 ]; then
    # Auto-fix: clean old logs and backups
    find /root/BettingPlatform/backups -mtime +7 -exec rm -rf {} + 2>/dev/null
    find /tmp -name "task-*.png" -mtime +1 -delete 2>/dev/null
    journalctl --vacuum-time=2d 2>/dev/null
    ISSUES+=("🧹 Auto-cleaned old backups/logs/screenshots")
  fi
fi

# 4. RAM usage
RAM_PCT=$(free | awk 'NR==2{printf "%d", $3/$2*100}')
if [ "$RAM_PCT" -gt 90 ]; then
  ISSUES+=("⚠️ RAM usage: ${RAM_PCT}%")
fi

# 5. MongoDB connection
if ! mongosh --eval "db.runCommand({ping:1})" --quiet betting 2>/dev/null | grep -q "ok"; then
  ISSUES+=("🔴 MongoDB not responding!")
fi

# 6. Stale events (no odds update in 30 min)
STALE=$(mongosh --quiet betting --eval "
  const cutoff = new Date(Date.now() - 30*60*1000);
  const count = db.events.countDocuments({isLive:true, oddsUpdatedAt:{\$lt:cutoff}});
  print(count);
" 2>/dev/null || echo "0")
if [ "$STALE" -gt 10 ]; then
  ISSUES+=("⚠️ ${STALE} live events with stale odds (30+ min)")
fi

# 7. API credits check (from aggregator log)
CREDITS=$(journalctl -u betting-aggregator --since '1 hour ago' --no-pager -q 2>/dev/null | grep -o 'credits.*' | tail -1)
if [ -n "$CREDITS" ]; then
  # Just log it, no alert unless critical
  :
fi

# Report
if [ ${#ISSUES[@]} -gt 0 ]; then
  MSG="🔍 Issue Detection Report:
$(printf '%s\n' "${ISSUES[@]}")"
  "$SCRIPT_DIR/send.sh" or 1 "$MSG"
  echo "$MSG"
  exit 1
else
  echo "✅ No issues detected"
  exit 0
fi
