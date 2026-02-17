#!/bin/bash
# Verify frontend — HTTP 200 + optional text match
# Usage: verify-frontend.sh <url> [expected_text]

URL="$1"
EXPECTED="$2"

if [ -z "$URL" ]; then
  echo "Usage: $0 <url> [expected_text]"
  echo "Example: $0 http://localhost:3000 'Welcome'"
  exit 1
fi

RESPONSE=$(curl -sS -o /tmp/verify-frontend-body.txt -w "%{http_code}" --max-time 10 "$URL" 2>/tmp/verify-frontend-err.txt)
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
  echo "❌ FAIL: curl error connecting to $URL — $(cat /tmp/verify-frontend-err.txt)"
  exit 1
fi

if [ "$RESPONSE" != "200" ]; then
  echo "❌ FAIL: $URL returned HTTP $RESPONSE (expected 200)"
  exit 1
fi

if [ -n "$EXPECTED" ]; then
  if ! grep -q "$EXPECTED" /tmp/verify-frontend-body.txt; then
    echo "❌ FAIL: $URL returned 200 but body does not contain '$EXPECTED'"
    exit 1
  fi
  echo "✅ PASS: $URL — HTTP 200, body contains '$EXPECTED'"
else
  echo "✅ PASS: $URL — HTTP 200"
fi
exit 0
