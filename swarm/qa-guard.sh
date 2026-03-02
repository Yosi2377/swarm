#!/bin/bash
# =============================================================================
# QA Guard — Post-change quality checks with regression detection
# Usage: qa-guard.sh <project_dir> [baseline_file]
# Output: JSON with status (pass/fail/regression), details, recommendations
# =============================================================================

set -uo pipefail

PROJECT_DIR="$1"
BASELINE_FILE="${2:-}"

if [ -z "$PROJECT_DIR" ]; then
  echo '{"status":"error","details":"Usage: qa-guard.sh <project_dir> [baseline_file]"}'
  exit 1
fi

cd "$PROJECT_DIR" || { echo '{"status":"error","details":"Cannot cd to project dir"}'; exit 1; }

# ---- Collectors ----

ISSUES=()
RECOMMENDATIONS=()
STATUS="pass"

add_issue() {
  ISSUES+=("$1")
}

add_rec() {
  RECOMMENDATIONS+=("$1")
}

# ---- 1. Detect and run tests ----

TEST_OUTPUT=""
TEST_EXIT=0

if [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
  TEST_OUTPUT=$(npm test -- --passWithNoTests 2>&1) && TEST_EXIT=0 || TEST_EXIT=$?
  TEST_RUNNER="npm test"
elif command -v pytest &>/dev/null && { [ -f "pytest.ini" ] || [ -d "tests" ]; }; then
  TEST_OUTPUT=$(pytest --tb=short 2>&1) && TEST_EXIT=0 || TEST_EXIT=$?
  TEST_RUNNER="pytest"
elif [ -f "Makefile" ] && grep -q '^test:' Makefile 2>/dev/null; then
  TEST_OUTPUT=$(make test 2>&1) && TEST_EXIT=0 || TEST_EXIT=$?
  TEST_RUNNER="make test"
else
  TEST_OUTPUT="No test runner detected"
  TEST_RUNNER="none"
fi

if [ "$TEST_EXIT" -ne 0 ] && [ "$TEST_RUNNER" != "none" ]; then
  STATUS="fail"
  add_issue "Tests failed (exit code $TEST_EXIT)"
fi

# ---- 2. Regression check against baseline ----

REGRESSION=false
if [ -n "$BASELINE_FILE" ] && [ -f "$BASELINE_FILE" ]; then
  BASELINE_STATUS=$(jq -r '.status // "unknown"' "$BASELINE_FILE" 2>/dev/null)
  if [ "$BASELINE_STATUS" = "pass" ] && [ "$TEST_EXIT" -ne 0 ]; then
    REGRESSION=true
    STATUS="regression"
    add_issue "REGRESSION: Tests that passed in baseline now fail"
    add_rec "Revert recent changes and isolate the breaking change"
  fi
fi

# ---- 3. Lint check ----

LINT_OUTPUT=""
LINT_STATUS="skipped"

if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f ".eslintrc" ] || [ -f "eslint.config.js" ]; then
  if command -v npx &>/dev/null; then
    LINT_OUTPUT=$(npx eslint . --max-warnings 0 2>&1) && LINT_STATUS="pass" || LINT_STATUS="warn"
    [ "$LINT_STATUS" = "warn" ] && add_rec "Fix lint warnings before merge"
  fi
elif [ -f ".pylintrc" ] || [ -f "setup.cfg" ]; then
  if command -v pylint &>/dev/null; then
    LINT_OUTPUT=$(pylint --errors-only $(find . -name "*.py" -not -path "*/node_modules/*" -not -path "*/.venv/*" | head -20) 2>&1) && LINT_STATUS="pass" || LINT_STATUS="warn"
    [ "$LINT_STATUS" = "warn" ] && add_rec "Fix pylint errors before merge"
  fi
fi

# ---- 4. Git diff review — forbidden changes ----

FORBIDDEN_CHANGES=()

# Check .env files
ENV_CHANGES=$(git diff --name-only HEAD~1 2>/dev/null | grep -E '\.env' || true)
if [ -n "$ENV_CHANGES" ]; then
  FORBIDDEN_CHANGES+=(".env files modified: $ENV_CHANGES")
  add_issue "Environment files were modified: $ENV_CHANGES"
  add_rec "Verify .env changes are intentional"
fi

# Check config files
CONFIG_CHANGES=$(git diff --name-only HEAD~1 2>/dev/null | grep -iE '(config\.(js|json|yaml|yml|ts)|\.conf$)' || true)
if [ -n "$CONFIG_CHANGES" ]; then
  FORBIDDEN_CHANGES+=("Config files modified: $CONFIG_CHANGES")
  add_rec "Review config file changes: $CONFIG_CHANGES"
fi

# Check package.json dependency changes (not scripts/version)
if git diff HEAD~1 -- package.json 2>/dev/null | grep -E '^\+.*"(dependencies|devDependencies)"' &>/dev/null; then
  FORBIDDEN_CHANGES+=("package.json dependencies changed")
  add_rec "Verify dependency changes are required for this task"
fi

# Check production/deployment files
DEPLOY_CHANGES=$(git diff --name-only HEAD~1 2>/dev/null | grep -iE '(dockerfile|docker-compose|\.github|\.gitlab|deploy|k8s|terraform|ansible)' || true)
if [ -n "$DEPLOY_CHANGES" ]; then
  FORBIDDEN_CHANGES+=("Deployment files modified: $DEPLOY_CHANGES")
  add_issue "Production/deployment files were modified"
  add_rec "Deployment file changes require explicit approval"
fi

# ---- 5. Build JSON output ----

# Convert arrays to JSON
ISSUES_JSON=$(printf '%s\n' "${ISSUES[@]:-}" | jq -R . | jq -s .)
RECS_JSON=$(printf '%s\n' "${RECOMMENDATIONS[@]:-}" | jq -R . | jq -s .)
FORBIDDEN_JSON=$(printf '%s\n' "${FORBIDDEN_CHANGES[@]:-}" | jq -R . | jq -s .)

CHANGED_COUNT=$(git diff --name-only HEAD~1 2>/dev/null | wc -l || echo 0)

jq -n \
  --arg status "$STATUS" \
  --arg test_runner "$TEST_RUNNER" \
  --argjson test_exit "$TEST_EXIT" \
  --arg test_output "$(echo "$TEST_OUTPUT" | head -50)" \
  --arg lint_status "$LINT_STATUS" \
  --arg lint_output "$(echo "$LINT_OUTPUT" | head -20)" \
  --argjson regression "$REGRESSION" \
  --argjson changed_files "$CHANGED_COUNT" \
  --argjson issues "$ISSUES_JSON" \
  --argjson recommendations "$RECS_JSON" \
  --argjson forbidden_changes "$FORBIDDEN_JSON" \
  --arg ts "$(date -Iseconds)" \
  '{
    status: $status,
    timestamp: $ts,
    tests: {runner: $test_runner, exit_code: $test_exit, output: $test_output},
    lint: {status: $lint_status, output: $lint_output},
    regression: $regression,
    changed_files: $changed_files,
    issues: $issues,
    recommendations: $recommendations,
    forbidden_changes: $forbidden_changes
  }'
