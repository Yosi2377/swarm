#!/bin/bash
# detect-issues.sh — Proactive issue detection + auto-fix
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISSUES=()

# 1. Server errors
for SVC in betting-backend betting-aggregator; do
  ERRS=$(journalctl -u $SVC --since '5 min ago' --no-pager -q 2>/dev/null | grep -ci 'error\|crash\|fatal\|ECONNREFUSED' || true)
  ERRS=${ERRS:-0}; ERRS=$(echo "$ERRS" | tr -dc '0-9'); ERRS=${ERRS:-0}
  if [ "$ERRS" -gt 3 ]; then
    SAMPLE=$(journalctl -u $SVC --since '5 min ago' --no-pager -q 2>/dev/null | grep -i 'error\|crash\|fatal' | tail -1 | cut -c1-100)
    ISSUES+=("🔴 $SVC: ${ERRS} errors — $SAMPLE")
  fi
done

# 2. Service down → auto-restart
for SVC in betting-backend betting-aggregator sandbox-betting-backend; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    ISSUES+=("🔴 $SVC is DOWN!")
    systemctl restart "$SVC" 2>/dev/null
    sleep 3
    if systemctl is-active --quiet "$SVC"; then
      ISSUES+=("✅ $SVC auto-restarted")
    else
      ISSUES+=("❌ $SVC restart FAILED")
    fi
  fi
done

# 3. Disk
DISK_PCT=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$DISK_PCT" -gt 85 ]; then
  ISSUES+=("⚠️ Disk: ${DISK_PCT}%")
  if [ "$DISK_PCT" -gt 95 ]; then
    find /root/BettingPlatform/backups -mtime +7 -exec rm -rf {} + 2>/dev/null
    find /tmp -name "task-*.png" -mtime +1 -delete 2>/dev/null
    journalctl --vacuum-time=2d 2>/dev/null
    ISSUES+=("🧹 Auto-cleaned old files")
  fi
fi

# 4. RAM
RAM_PCT=$(free | awk 'NR==2{printf "%d", $3/$2*100}')
if [ "$RAM_PCT" -gt 90 ]; then
  ISSUES+=("⚠️ RAM: ${RAM_PCT}%")
fi

# 5. MongoDB
if ! mongosh --eval "db.runCommand({ping:1})" --quiet betting 2>/dev/null | grep -q "ok"; then
  ISSUES+=("🔴 MongoDB not responding!")
fi

# 6. Stale live events
STALE=$(mongosh --quiet betting --eval "
const c=new Date(Date.now()-30*60*1000);
print(db.events.countDocuments({isLive:true,oddsUpdatedAt:{\$lt:c}}));
" 2>/dev/null || echo "0")
if [ "$STALE" -gt 10 ]; then
  ISSUES+=("⚠️ ${STALE} live events stale 30+ min")
fi

# Report + Auto-create fix task
if [ ${#ISSUES[@]} -gt 0 ]; then
  MSG="🔍 Issues Detected:
$(printf '%s\n' "${ISSUES[@]}")"
  "$SCRIPT_DIR/send.sh" or 1 "$MSG" 2>/dev/null
  echo "$MSG"
  
  # Auto-create task for code-fixable issues
  for ISSUE in "${ISSUES[@]}"; do
    if echo "$ISSUE" | grep -q "stale.*events"; then
      # Create delegation to fix stale odds
      bash "$SCRIPT_DIR/delegate.sh" or koder "Fix stale odds: restart aggregator sync cycle" 2>/dev/null
      systemctl restart betting-aggregator 2>/dev/null
      echo "🔧 Auto-fix: restarted aggregator for stale odds"
    fi
    if echo "$ISSUE" | grep -q "DOWN.*FAILED"; then
      # Critical: alert immediately
      "$SCRIPT_DIR/send.sh" or 1 "🚨 CRITICAL: Service down and auto-restart failed! Manual intervention needed." 2>/dev/null
    fi
  done
  exit 1
else
  echo "✅ No issues"
  exit 0
fi
