#!/bin/bash
# Called when user clicks Approve
TASK_ID="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# 1. Snapshot before deploy
bash swarm/snapshot.sh create "pre-deploy-${TASK_ID}"

# 2. Find changed files in sandbox
SANDBOX="/root/sandbox/BettingPlatform/backend/public"
PROD="/root/BettingPlatform/backend/public"

# 3. Deploy sandbox → production
for f in $(find $SANDBOX -name "*.html" -o -name "*.js" -newer /tmp/task-${TASK_ID}-pipeline.png 2>/dev/null); do
  REL=${f#$SANDBOX/}
  DEST="$PROD/$REL"
  chattr -i "$DEST" 2>/dev/null
  cp "$f" "$DEST"
  chattr +i "$DEST" 2>/dev/null
done

# 4. Restart production
systemctl restart betting-backend

# 5. Wait and verify
sleep 5
HTTP=$(curl -s -o /dev/null -w '%{http_code}' http://95.111.247.22:8089)
if [ "$HTTP" = "200" ]; then
  bash "$SCRIPT_DIR/send.sh" or 1 "✅ PR #${TASK_ID} deployed to production! HTTP: $HTTP"
else
  # AUTO ROLLBACK
  bash swarm/snapshot.sh restore "pre-deploy-${TASK_ID}"
  bash "$SCRIPT_DIR/send.sh" or 1 "🔴 PR #${TASK_ID} deploy FAILED (HTTP: $HTTP) — AUTO ROLLBACK completed"
fi
