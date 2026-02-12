#!/bin/bash
# Backup a project directory before task starts
# Usage: ./backup.sh <path> [label]
# Example: ./backup.sh /root/Blackjack-Game-Multiplayer blackjack-pre-fix

SOURCE_PATH="$1"
LABEL="${2:-$(basename "$1")}"
BACKUP_DIR="/root/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${LABEL}_${TIMESTAMP}.tar.gz"

if [ -z "$SOURCE_PATH" ] || [ ! -d "$SOURCE_PATH" ]; then
  echo "Usage: $0 <path> [label]"
  echo "Path must be an existing directory"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

# Create tar.gz excluding node_modules, .git, and build artifacts
tar -czf "$BACKUP_FILE" \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='build' \
  --exclude='dist' \
  -C "$(dirname "$SOURCE_PATH")" "$(basename "$SOURCE_PATH")" 2>/dev/null

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✅ Backup created: $BACKUP_FILE ($SIZE)"

# Cleanup: keep only last 10 backups per label
ls -t "$BACKUP_DIR/${LABEL}_"*.tar.gz 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null

echo "$BACKUP_FILE"
