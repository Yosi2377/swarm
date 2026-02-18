#!/bin/bash
# gen-tests.sh — Auto-generate browser test JSON from an HTML file
# Usage: gen-tests.sh FILE_PATH TASK_ID

set -euo pipefail

FILE_PATH="${1:?Usage: gen-tests.sh FILE_PATH TASK_ID}"
TASK_ID="${2:?Usage: gen-tests.sh FILE_PATH TASK_ID}"
TESTS_DIR="$(dirname "$0")/tests"
OUTPUT="$TESTS_DIR/$TASK_ID.json"

mkdir -p "$TESTS_DIR"

if [[ ! -f "$FILE_PATH" ]]; then
  echo "❌ File not found: $FILE_PATH"
  exit 1
fi

# Extract classes and IDs
CLASSES=$(grep -oP 'class="[^"]+"' "$FILE_PATH" | sed 's/class="//;s/"//' | tr ' ' '\n' | sort -u | head -20)
IDS=$(grep -oP 'id="[^"]+"' "$FILE_PATH" | sed 's/id="//;s/"//' | sort -u | head -20)

# Git diff — new lines (ignore errors if not in git)
DIFF_CLASSES=""
DIFF_IDS=""
if git diff HEAD -- "$FILE_PATH" 2>/dev/null | grep "^+" | grep -oP 'class="[^"]+"' 2>/dev/null; then
  DIFF_CLASSES=$(git diff HEAD -- "$FILE_PATH" | grep "^+" | grep -oP 'class="[^"]+"' | sed 's/class="//;s/"//' | tr ' ' '\n' | sort -u)
fi
if git diff HEAD -- "$FILE_PATH" 2>/dev/null | grep "^+" | grep -oP 'id="[^"]+"' 2>/dev/null; then
  DIFF_IDS=$(git diff HEAD -- "$FILE_PATH" | grep "^+" | grep -oP 'id="[^"]+"' | sed 's/id="//;s/"//' | sort -u)
fi

# Build JSON tests array
TESTS='[
  {"type": "exists", "selector": "body", "desc": "Page loads"}'

# Add class-based tests (prioritize diff classes, then all)
SELECTED_CLASSES="$DIFF_CLASSES"
if [[ -z "$SELECTED_CLASSES" ]]; then
  SELECTED_CLASSES="$CLASSES"
fi

for CLASS in $SELECTED_CLASSES; do
  [[ -z "$CLASS" ]] && continue
  TESTS="$TESTS,"$'\n'"  {\"type\": \"exists\", \"selector\": \".$CLASS\", \"desc\": \"$CLASS exists\"}"
done

# Add ID-based tests (prioritize diff IDs, then all)
SELECTED_IDS="$DIFF_IDS"
if [[ -z "$SELECTED_IDS" ]]; then
  SELECTED_IDS="$IDS"
fi

for ID in $SELECTED_IDS; do
  [[ -z "$ID" ]] && continue
  TESTS="$TESTS,"$'\n'"  {\"type\": \"exists\", \"selector\": \"#$ID\", \"desc\": \"$ID exists\"}"
done

# Add noErrors and screenshot
TESTS="$TESTS,"$'\n'"  {\"type\": \"noErrors\", \"desc\": \"No JS errors\"}"
TESTS="$TESTS,"$'\n'"  {\"type\": \"screenshot\", \"path\": \"/tmp/test-$TASK_ID.png\"}"
TESTS="$TESTS"$'\n]'

# Write JSON
echo "{\"tests\": $TESTS}" | python3 -m json.tool > "$OUTPUT"

echo "✅ Generated $OUTPUT"
echo "📋 Tests: $(python3 -c "import json;print(len(json.load(open('$OUTPUT'))['tests']))")"

# Run browser-eval if available
SCRIPT_DIR="$(dirname "$0")"
if [[ -f "$SCRIPT_DIR/browser-eval.js" ]]; then
  echo "🌐 Running browser tests..."
  node "$SCRIPT_DIR/browser-eval.js" "http://95.111.247.22:9089" "$OUTPUT" 2>&1 || true
fi
