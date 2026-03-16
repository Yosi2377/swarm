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

## CHECK 4: Pipeline validation — current step must be "deploy" and review must be "done"
PIPELINE_DIR="/root/.openclaw/workspace/swarm/tasks"
# Find pipeline file for this thread
PIPELINE_FILE=""
for pf in "$PIPELINE_DIR"/*.pipeline.json; do
  [ -f "$pf" ] || continue
  PF_THREAD=$(python3 -c "import json;print(json.load(open('$pf')).get('thread_id',''))" 2>/dev/null)
  if [ "$PF_THREAD" = "$THREAD" ]; then
    PIPELINE_FILE="$pf"
    break
  fi
done

if [ -n "$PIPELINE_FILE" ]; then
  PF_STEP=$(python3 -c "import json;print(json.load(open('$PIPELINE_FILE'))['current_step'])" 2>/dev/null)
  PF_REVIEW=$(python3 -c "import json;print(json.load(open('$PIPELINE_FILE'))['steps']['review'])" 2>/dev/null)
  if [ "$PF_STEP" != "deploy" ]; then
    echo "❌ PIPELINE BLOCK: current step is '$PF_STEP', must be 'deploy'"
    $SEND or 1 "⛔ #${THREAD} — deploy blocked! Pipeline step = $PF_STEP (need deploy)"
    exit 1
  fi
  if [ "$PF_REVIEW" != "done" ]; then
    echo "❌ PIPELINE BLOCK: review step is '$PF_REVIEW', must be 'done' (approved)"
    $SEND or 1 "⛔ #${THREAD} — deploy blocked! Review not approved"
    exit 1
  fi
  echo "✅ Pipeline check passed (step=deploy, review=done)"
else
  echo "⚠️ No pipeline file found for thread $THREAD — proceeding with approval-only check"
fi

echo "✅ All checks passed. Deploying..."

# UNLOCK production (only deploy.sh can do this)
find "$PROD/backend/public" -type f -exec chattr -i {} \; 2>/dev/null
find "$PROD/backend/public" -type d -exec chattr -i {} \; 2>/dev/null

# COPY from sandbox
rsync -a --delete "$SANDBOX/backend/public/" "$PROD/backend/public/"

# COMMIT (with DEPLOY_SH_RUNNING to bypass pre-commit hook)
cd "$PROD" && git add -A && DEPLOY_SH_RUNNING=1 git commit -m "deploy: #${THREAD} from sandbox (approved)" 2>&1

# RESTART
systemctl restart "$SERVICE"

# LOCK production again — immutable flag on all deployed files
echo "🔒 Locking production files with chattr +i..."
find "$PROD/backend/public" -type f -exec chattr +i {} \; 2>/dev/null
find "$PROD/backend/public" -type d -exec chattr +i {} \; 2>/dev/null
LOCKED_COUNT=$(find "$PROD/backend/public" -type f | wc -l)
echo "🔒 Locked $LOCKED_COUNT files in $PROD/backend/public"

# CLEANUP
rm -f "$APPROVAL"

# REPORT
$SEND or 1 "✅ #${THREAD} — deployed to production + locked 🔒"

echo "✅ Deployed + locked!"
