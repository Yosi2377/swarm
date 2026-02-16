#!/bin/bash
# deploy.sh — THE ONLY WAY to deploy to production
# Usage: deploy.sh <project> <thread_id>
# Checks: sandbox exists, approval file exists, then unlocks + copies + locks

set -e

PROJECT="$1"
THREAD="$2"
SEND="/root/.openclaw/workspace/swarm/send.sh"

if [ -z "$PROJECT" ] || [ -z "$THREAD" ]; then
  echo "❌ Usage: deploy.sh <project> <thread_id>"
  echo "   project: betting / poker"
  exit 1
fi

# Project paths
case "$PROJECT" in
  betting)
    PROD="/root/BettingPlatform"
    SANDBOX="/root/sandbox/BettingPlatform"
    SERVICE="betting-backend"
    ;;
  poker)
    PROD="/root/TexasPokerGame"
    SANDBOX="/root/sandbox/TexasPokerGame"
    SERVICE="texas-poker"
    ;;
  *)
    echo "❌ Unknown project: $PROJECT"
    exit 1
    ;;
esac

# CHECK 1: Sandbox exists and has changes
if [ ! -d "$SANDBOX" ]; then
  echo "❌ Sandbox not found: $SANDBOX"
  exit 1
fi

SANDBOX_COMMIT=$(cd "$SANDBOX" && git log -1 --format="%H" 2>/dev/null)
PROD_COMMIT=$(cd "$PROD" && git log -1 --format="%H" 2>/dev/null)

if [ "$SANDBOX_COMMIT" = "$PROD_COMMIT" ]; then
  echo "❌ No changes in sandbox vs production"
  exit 1
fi

# CHECK 2: Approval file exists (created by user saying "מאשר")
APPROVAL="/tmp/production-approved-${PROJECT}"
if [ ! -f "$APPROVAL" ]; then
  echo "❌ NO APPROVAL! File missing: $APPROVAL"
  echo "   Yossi must approve first. Then: touch $APPROVAL"
  $SEND or 1 "⛔ #${THREAD} — deploy נחסם! אין אישור יוסי."
  exit 1
fi

# CHECK 3: Approval not expired (30 min)
APPROVAL_AGE=$(( $(date +%s) - $(stat -c %Y "$APPROVAL") ))
if [ "$APPROVAL_AGE" -gt 1800 ]; then
  echo "❌ Approval expired (${APPROVAL_AGE}s old, max 1800s)"
  rm -f "$APPROVAL"
  exit 1
fi

echo "✅ All checks passed. Deploying..."

# UNLOCK production
find "$PROD/backend/public" -type f -exec chattr -i {} \; 2>/dev/null
find "$PROD/backend/public" -type d -exec chattr -i {} \; 2>/dev/null

# COPY from sandbox
rsync -a --delete "$SANDBOX/backend/public/" "$PROD/backend/public/"

# COMMIT
cd "$PROD" && git add -A && git commit -m "deploy: #${THREAD} from sandbox (approved)" 2>&1

# RESTART
systemctl restart "$SERVICE"

# LOCK production again
find "$PROD/backend/public" -type f -exec chattr +i {} \; 2>/dev/null
find "$PROD/backend/public" -type d -exec chattr +i {} \; 2>/dev/null

# CLEANUP
rm -f "$APPROVAL"

# REPORT
$SEND or 1 "✅ #${THREAD} — deployed to production + locked 🔒"

echo "✅ Deployed + locked!"
