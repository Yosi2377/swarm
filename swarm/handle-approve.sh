#!/bin/bash
# handle-approve.sh — Deploy sandbox → production after PR approval
# Usage: handle-approve.sh TASK_ID
TASK_ID="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$TASK_ID" ]; then
  echo "Usage: handle-approve.sh TASK_ID"
  exit 1
fi

cd "$SCRIPT_DIR/.."

# 1. Snapshot before deploy
bash swarm/snapshot.sh create "pre-deploy-${TASK_ID}" 2>&1

# 2. Deploy sandbox → production
SANDBOX="/root/sandbox/BettingPlatform/backend/public"
PROD="/root/BettingPlatform/backend/public"

# Deploy HTML files
for f in index.html admin.html agent.html; do
  if [ -f "$SANDBOX/$f" ]; then
    chattr -i "$PROD/$f" 2>/dev/null
    cp "$SANDBOX/$f" "$PROD/$f"
    chattr +i "$PROD/$f" 2>/dev/null
    echo "✅ Deployed $f"
  fi
done

# Deploy new/changed assets (png, ico, css, js in public root)
chattr -i "$PROD" 2>/dev/null
for f in $(find "$SANDBOX" -maxdepth 1 -newer /tmp/task-${TASK_ID}-pipeline.png -name "*.png" -o -name "*.ico" -o -name "*.svg" -o -name "*.css" 2>/dev/null); do
  NAME=$(basename "$f")
  chattr -i "$PROD/$NAME" 2>/dev/null
  cp "$f" "$PROD/$NAME"
  chattr +i "$PROD/$NAME" 2>/dev/null
  echo "✅ Deployed asset: $NAME"
done
chattr +i "$PROD" 2>/dev/null

# 3. Restart production
systemctl restart betting-backend
sleep 5

# 4. Verify (HTTP + content check)
HTTP=$(curl -s -o /dev/null -w '%{http_code}' http://95.111.247.22:8089)
CONTENT=$(curl -s http://95.111.247.22:8089 | grep -c "ZozoBet")
if [ "$HTTP" = "200" ] && [ "$CONTENT" -gt 0 ]; then
  "$SCRIPT_DIR/send.sh" or 1 "✅ PR #${TASK_ID} deployed! HTTP: $HTTP, Content: ✅"
  echo "✅ Deploy successful"
else
  # AUTO ROLLBACK
  echo "🔴 Verify failed (HTTP: $HTTP, Content: $CONTENT) — rolling back!"
  cd "$SCRIPT_DIR/.."
  bash swarm/snapshot.sh restore "pre-deploy-${TASK_ID}"
  "$SCRIPT_DIR/send.sh" or 1 "🔴 PR #${TASK_ID} FAILED (HTTP: $HTTP, Content: $CONTENT) — AUTO ROLLBACK!"
  echo "🔴 Deploy failed — rolled back"
  exit 1
fi
