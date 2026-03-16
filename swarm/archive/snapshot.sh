#!/bin/bash
# snapshot.sh — Auto Rollback System
# Usage: snapshot.sh <ACTION> <TAG>
# ACTION: create | restore

ACTION="$1"
TAG="$2"

if [[ -z "$ACTION" || -z "$TAG" ]]; then
  echo "❌ Usage: snapshot.sh <create|restore> <TAG>"
  exit 1
fi

case "$ACTION" in
  create)
    TAG_FULL="deploy-${TAG}-$(date +%Y%m%d-%H%M%S)"
    cd /root/.openclaw/workspace && git tag "$TAG_FULL" 2>/dev/null
    mkdir -p /root/BettingPlatform/backups/${TAG_FULL}
    cp -r /root/BettingPlatform/backend /root/BettingPlatform/backups/${TAG_FULL}/
    cp -r /root/BettingPlatform/aggregator /root/BettingPlatform/backups/${TAG_FULL}/
    mongodump --db betting --out /root/BettingPlatform/backups/${TAG_FULL}/db 2>/dev/null
    echo "✅ Snapshot saved: ${TAG_FULL}"
    ;;
  restore)
    BACKUP=$(ls -d /root/BettingPlatform/backups/deploy-${TAG}* 2>/dev/null | tail -1)
    if [[ -z "$BACKUP" ]]; then
      echo "❌ No backup found for TAG: ${TAG}"
      exit 1
    fi
    find /root/BettingPlatform/backend -type f \( -name "*.js" -o -name "*.html" \) | xargs chattr -i 2>/dev/null
    cp -r ${BACKUP}/backend/* /root/BettingPlatform/backend/
    cp -r ${BACKUP}/aggregator/* /root/BettingPlatform/aggregator/
    systemctl restart betting-backend betting-aggregator
    find /root/BettingPlatform/backend -type f \( -name "*.js" -o -name "*.html" \) | xargs chattr +i 2>/dev/null
    /root/.openclaw/workspace/swarm/send.sh or 1 "⏪ Rollback to ${TAG} completed"
    echo "✅ Restored from: ${BACKUP}"
    ;;
  *)
    echo "❌ Unknown action: ${ACTION}. Use 'create' or 'restore'."
    exit 1
    ;;
esac
