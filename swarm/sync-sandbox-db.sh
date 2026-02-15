#!/bin/bash
# sync-sandbox-db.sh — Copy production DB to sandbox (one-way, read-only copy)
# Usage: sync-sandbox-db.sh [--once]
# Without --once: runs every 10 minutes
# Collections synced: events, odds (read-only data)
# Collections NOT synced: users, bets, transactions, periods (sandbox has its own)

set -uo pipefail

PROD_DB="betting"
SANDBOX_DB="betting_sandbox"
COLLECTIONS="events"  # Only events (contains odds too)

sync_once() {
  echo "[$(date '+%H:%M:%S')] Syncing $PROD_DB → $SANDBOX_DB..."
  
  for col in $COLLECTIONS; do
    # Export from production
    mongodump --db="$PROD_DB" --collection="$col" --out=/tmp/db-sync --quiet 2>/dev/null
    
    # Drop sandbox collection and import
    mongosh --quiet "$SANDBOX_DB" --eval "db.${col}.drop()" 2>/dev/null
    mongorestore --db="$SANDBOX_DB" --collection="$col" --dir="/tmp/db-sync/${PROD_DB}/${col}.bson" --quiet 2>/dev/null
    
    COUNT=$(mongosh --quiet "$SANDBOX_DB" --eval "db.${col}.countDocuments()" 2>/dev/null)
    echo "  ✅ $col: $COUNT documents"
  done
  
  rm -rf /tmp/db-sync
  echo "[$(date '+%H:%M:%S')] Sync complete"
}

# Initialize sandbox DB with users/settings if empty
init_sandbox() {
  USER_COUNT=$(mongosh --quiet "$SANDBOX_DB" --eval "db.users.countDocuments()" 2>/dev/null || echo "0")
  if [ "$USER_COUNT" = "0" ]; then
    echo "🔧 Initializing sandbox DB with users from production..."
    mongodump --db="$PROD_DB" --collection="users" --out=/tmp/db-sync-init --quiet 2>/dev/null
    mongorestore --db="$SANDBOX_DB" --collection="users" --dir="/tmp/db-sync-init/${PROD_DB}/users.bson" --quiet 2>/dev/null
    rm -rf /tmp/db-sync-init
    
    UCOUNT=$(mongosh --quiet "$SANDBOX_DB" --eval "db.users.countDocuments()" 2>/dev/null)
    echo "  ✅ users: $UCOUNT copied (one-time init)"
  fi
}

# First run
init_sandbox
sync_once

if [ "${1:-}" = "--once" ]; then
  exit 0
fi

# Loop every 10 minutes
while true; do
  sleep 600
  sync_once
done
