#!/bin/bash
# gen-tests.sh — Auto-generate browser test JSON from an HTML file
# Usage: gen-tests.sh FILE_PATH TASK_ID [PORT]

set -euo pipefail

FILE_PATH="${1:?Usage: gen-tests.sh FILE_PATH TASK_ID [PORT]}"
TASK_ID="${2:?Usage: gen-tests.sh FILE_PATH TASK_ID [PORT]}"
PORT="${3:-}"
TESTS_DIR="$(dirname "$0")/tests"
OUTPUT="$TESTS_DIR/$TASK_ID.json"
SCRIPT_DIR="$(dirname "$0")"

mkdir -p "$TESTS_DIR"

if [[ ! -f "$FILE_PATH" ]]; then
  echo "❌ File not found: $FILE_PATH"
  exit 1
fi

# Determine URL based on filename — admin files → admin.html, otherwise main page
BASE_URL="http://95.111.247.22:${PORT:-9089}"
BASENAME="$(basename "$FILE_PATH")"
if [[ "$BASENAME" == *admin* ]]; then
  URL="$BASE_URL/admin.html"
elif [[ "$BASENAME" == "index.html" ]]; then
  URL="$BASE_URL/"
else
  URL="$BASE_URL/$BASENAME"
fi

# Extract classes and IDs from the file
CLASSES=$(grep -oP 'class="[^"]+"' "$FILE_PATH" | sed 's/class="//;s/"//' | tr ' ' '\n' | grep -v '[${}()+'"'"']' | grep -v '^\s*$' | sort -u || true)
IDS=$(grep -oP 'id="[^"]+"' "$FILE_PATH" | sed 's/id="//;s/"//' | grep -v '[${}()+'"'"']' | grep -v '^\s*$' | sort -u || true)

# Priority selectors — test these first if they exist
PRIORITY_CLASSES="c-match bal auth-wrap container main-content header footer nav sidebar"
PRIORITY_IDS="app root main"

# Build test list (max 15)
TESTS='[
  {"type": "exists", "selector": "body", "desc": "Page loads"}'
COUNT=1
MAX=15

# Add priority classes that exist in the file
for PC in $PRIORITY_CLASSES; do
  [[ $COUNT -ge $MAX ]] && break
  if echo "$CLASSES" | grep -qx "$PC"; then
    TESTS="$TESTS,"$'\n'"  {\"type\": \"exists\", \"selector\": \".$PC\", \"desc\": \".$PC exists\"}"
    COUNT=$((COUNT + 1))
  fi
done

# Add priority IDs that exist in the file
for PI in $PRIORITY_IDS; do
  [[ $COUNT -ge $MAX ]] && break
  if echo "$IDS" | grep -qx "$PI"; then
    TESTS="$TESTS,"$'\n'"  {\"type\": \"exists\", \"selector\": \"#$PI\", \"desc\": \"#$PI exists\"}"
    COUNT=$((COUNT + 1))
  fi
done

# Fill remaining with other classes (skip already added)
for CLASS in $CLASSES; do
  [[ $COUNT -ge $((MAX - 2)) ]] && break
  [[ -z "$CLASS" ]] && continue
  echo "$PRIORITY_CLASSES" | tr ' ' '\n' | grep -qx "$CLASS" && continue
  TESTS="$TESTS,"$'\n'"  {\"type\": \"exists\", \"selector\": \".$CLASS\", \"desc\": \".$CLASS exists\"}"
  COUNT=$((COUNT + 1))
done

# Fill remaining with other IDs (skip already added)
for ID in $IDS; do
  [[ $COUNT -ge $((MAX - 2)) ]] && break
  [[ -z "$ID" ]] && continue
  echo "$PRIORITY_IDS" | tr ' ' '\n' | grep -qx "$ID" && continue
  TESTS="$TESTS,"$'\n'"  {\"type\": \"exists\", \"selector\": \"#$ID\", \"desc\": \"#$ID exists\"}"
  COUNT=$((COUNT + 1))
done

# Always add noErrors and screenshot at end
TESTS="$TESTS,"$'\n'"  {\"type\": \"noErrors\", \"desc\": \"No JS errors\"}"
TESTS="$TESTS,"$'\n'"  {\"type\": \"screenshot\", \"path\": \"/tmp/test-$TASK_ID.png\"}"
TESTS="$TESTS"$'\n'"]"

# Write JSON with URL
echo "{\"url\": \"$URL\", \"tests\": $TESTS}" | python3 -m json.tool > "$OUTPUT"

TOTAL=$(python3 -c "import json;print(len(json.load(open('$OUTPUT'))['tests']))")
echo "✅ Generated $OUTPUT ($TOTAL tests, URL: $URL)"
