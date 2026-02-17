#!/bin/bash
# Verify deployment — combines service + frontend checks
# Usage: verify-deploy.sh <service_name> <url> [expected_text]

SERVICE="$1"
URL="$2"
EXPECTED="$3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$SERVICE" ] || [ -z "$URL" ]; then
  echo "Usage: $0 <service_name> <url> [expected_text]"
  echo "Example: $0 betting-api http://localhost:4000 'OK'"
  exit 1
fi

echo "--- Checking service: $SERVICE ---"
"$SCRIPT_DIR/verify-service.sh" "$SERVICE"
SVC_RESULT=$?

echo "--- Checking URL: $URL ---"
"$SCRIPT_DIR/verify-frontend.sh" "$URL" "$EXPECTED"
URL_RESULT=$?

if [ $SVC_RESULT -ne 0 ] || [ $URL_RESULT -ne 0 ]; then
  echo "❌ FAIL: Deploy verification failed for $SERVICE / $URL"
  exit 1
fi

echo "✅ PASS: Deploy verified — $SERVICE active + $URL responding"
exit 0
