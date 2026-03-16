#!/bin/bash
# verify-agent.sh — Run after agent reports done to verify their work
# Usage: verify-agent.sh <project_dir> <test_command>
# Returns: exit 0 if tests pass, exit 1 if they fail
# Outputs: test results to stdout

PROJECT_DIR="${1:?Usage: verify-agent.sh <project_dir> <test_command>}"
TEST_CMD="${2:-npm test}"

echo "🔍 Verifying agent work in ${PROJECT_DIR}..."
echo "Running: ${TEST_CMD}"
echo "========================================="

cd "$PROJECT_DIR" || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }

# Run the test command, capture output and exit code
OUTPUT=$(eval "$TEST_CMD" 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"
echo "========================================="

if [ $EXIT_CODE -eq 0 ]; then
    PASSED=$(echo "$OUTPUT" | grep -c "✅")
    FAILED=$(echo "$OUTPUT" | grep -c "❌")
    if [ "$FAILED" -gt 0 ]; then
        echo "⚠️ VERIFICATION FAILED: Tests exited 0 but found $FAILED failures in output!"
        exit 1
    fi
    echo "✅ VERIFICATION PASSED: $PASSED tests passed, exit code 0"
    exit 0
else
    FAILED=$(echo "$OUTPUT" | grep -c "❌")
    echo "❌ VERIFICATION FAILED: exit code $EXIT_CODE, $FAILED test failures"
    exit 1
fi
