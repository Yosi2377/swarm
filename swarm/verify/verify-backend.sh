#!/bin/bash
# Verify backend — API health check + endpoint validation
# Usage: verify-backend.sh <base_url> [endpoint]

BASE_URL="$1"
ENDPOINT="${2:-/api/health}"

if [ -z "$BASE_URL" ]; then
  echo "Usage: $0 <base_url> [endpoint]"
  echo "Example: $0 http://localhost:4000 /api/health"
  exit 1
fi

FULL_URL="${BASE_URL}${ENDPOINT}"
RESPONSE=$(curl -sS -o /tmp/verify-backend-body.txt -w "%{http_code}" --max-time 10 "$FULL_URL" 2>/tmp/verify-backend-err.txt)
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
  echo "❌ FAIL: Cannot connect to $FULL_URL — $(cat /tmp/verify-backend-err.txt)"
  exit 1
fi

if [ "$RESPONSE" -lt 200 ] || [ "$RESPONSE" -ge 300 ]; then
  echo "❌ FAIL: $FULL_URL returned HTTP $RESPONSE"
  exit 1
fi

BODY=$(cat /tmp/verify-backend-body.txt)
# Check for common error indicators in JSON response
if echo "$BODY" | grep -qi '"error"'; then
  echo "❌ FAIL: $FULL_URL returned error in body: $(echo "$BODY" | head -c 200)"
  exit 1
fi

echo "✅ PASS: $FULL_URL — HTTP $RESPONSE, no errors in response"
exit 0
