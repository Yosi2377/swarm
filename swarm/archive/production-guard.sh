#!/bin/bash
# production-guard.sh — BLOCKS any cp/rsync from sandbox to production
# Must be called before any deploy. Returns 1 = BLOCKED, 0 = APPROVED
# Usage: source production-guard.sh <project>
#
# Checks /tmp/production-approved-<project> file
# Only the user can create this file (via send.sh approval flow)

PROJECT="${1:?Usage: production-guard.sh <project>}"
APPROVAL_FILE="/tmp/production-approved-${PROJECT}"

if [ -f "$APPROVAL_FILE" ]; then
  # Check if approval is less than 30 minutes old
  AGE=$(( $(date +%s) - $(stat -c %Y "$APPROVAL_FILE") ))
  if [ "$AGE" -lt 1800 ]; then
    echo "✅ Production deploy approved (${AGE}s ago)"
    rm -f "$APPROVAL_FILE"  # One-time use
    exit 0
  else
    echo "⛔ Approval expired (${AGE}s old, max 1800s)"
    rm -f "$APPROVAL_FILE"
    exit 1
  fi
fi

echo "⛔ BLOCKED — No user approval for production deploy"
echo "User must approve first. File missing: $APPROVAL_FILE"
exit 1
