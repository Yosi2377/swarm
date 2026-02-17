#!/bin/bash
# Verify systemd service — is-active + no recent errors
# Usage: verify-service.sh <service_name>

SERVICE="$1"

if [ -z "$SERVICE" ]; then
  echo "Usage: $0 <service_name>"
  echo "Example: $0 nginx"
  exit 1
fi

# Check if service is active
STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null)
if [ "$STATUS" != "active" ]; then
  echo "❌ FAIL: Service $SERVICE is $STATUS"
  exit 1
fi

# Check for errors in last 2 minutes
ERRORS=$(journalctl -u "$SERVICE" --since "2 minutes ago" -p err --no-pager -q 2>/dev/null | head -5)
if [ -n "$ERRORS" ]; then
  echo "❌ FAIL: Service $SERVICE is active but has recent errors:"
  echo "$ERRORS"
  exit 1
fi

echo "✅ PASS: Service $SERVICE is active, no errors in last 2 minutes"
exit 0
