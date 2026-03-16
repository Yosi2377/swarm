#!/bin/bash
# test-runner.sh <project> <thread_id>
# Runs all relevant tests and returns PASS/FAIL + details
set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${1:?Usage: test-runner.sh <project|auto> <thread_id>}"
THREAD="${2:-}"

PASSED=0
FAILED=0
ERRORS=""
TOTAL=0

run_test() {
  local desc="$1"
  local cmd="$2"
  local expect="${3:-}"
  TOTAL=$((TOTAL + 1))
  
  output=$(eval "$cmd" 2>&1) || true
  rc=$?
  
  local ok=false
  if [ -n "$expect" ]; then
    case "$expect" in
      "active") [[ "$output" == *"active"* ]] && ok=true ;;
      "200"|"301"|"302") [[ "$output" == *"$expect"* ]] && ok=true ;;
      ">0") [[ "$output" =~ [1-9][0-9]* ]] && ok=true ;;
      "json_array") echo "$output" | python3 -c "import sys,json;d=json.load(sys.stdin);assert isinstance(d,list)" 2>/dev/null && ok=true ;;
      "has_key:"*) 
        key="${expect#has_key:}"
        echo "$output" | python3 -c "import sys,json;d=json.load(sys.stdin);assert '$key' in d" 2>/dev/null && ok=true ;;
      "non_empty") [[ -n "$output" ]] && ok=true ;;
      *) [[ "$output" == *"$expect"* ]] && ok=true ;;
    esac
  else
    [[ $rc -eq 0 ]] && ok=true
  fi
  
  if $ok; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    ERRORS="${ERRORS}\n  ❌ Test $TOTAL: $desc — got: $(echo "$output" | head -c 200)"
  fi
}

# Project-specific tests
case "$PROJECT" in
  betting)
    run_test "betting-backend service" "systemctl is-active betting-backend" "active"
    run_test "betting-aggregator service" "systemctl is-active betting-aggregator" "active"
    run_test "API /api/events" "curl -sf http://localhost:8089/api/events" "json_array"
    run_test "API events count >0" "curl -sf http://localhost:8089/api/events | python3 -c \"import sys,json;print(len(json.load(sys.stdin)))\"" ">0"
    run_test "MongoDB events" "mongosh --quiet --eval 'db.events.countDocuments()' betting 2>/dev/null" ">0"
    ;;
  poker)
    run_test "texas-poker service" "systemctl is-active texas-poker" "active"
    run_test "poker site responds" "curl -so /dev/null -w '%{http_code}' -m5 https://zozopoker.duckdns.org" "200"
    ;;
  dashboard)
    run_test "dashboard responds" "curl -so /dev/null -w '%{http_code}' -m5 http://localhost:8090" "200"
    run_test "agents/live endpoint" "curl -sf http://localhost:8090/api/agents/live" "json_array"
    run_test "tasks endpoint" "curl -sf http://localhost:8090/api/tasks" "has_key:tasks"
    ;;
  auto)
    # Detect project from thread task file
    if [ -n "$THREAD" ] && [ -f "$SWARM_DIR/tasks/${THREAD}.md" ]; then
      task_content=$(cat "$SWARM_DIR/tasks/${THREAD}.md")
      if echo "$task_content" | grep -qi "betting\|הימור"; then
        PROJECT="betting"
      elif echo "$task_content" | grep -qi "poker\|פוקר"; then
        PROJECT="poker"
      elif echo "$task_content" | grep -qi "dashboard\|דאשבורד"; then
        PROJECT="dashboard"
      fi
      [ "$PROJECT" != "auto" ] && exec "$0" "$PROJECT" "$THREAD"
    fi
    echo "SKIP: Could not auto-detect project"
    exit 0
    ;;
esac

# Custom tests from task file
if [ -n "$THREAD" ] && [ -f "$SWARM_DIR/tasks/${THREAD}.md" ]; then
  in_tests=false
  while IFS= read -r line; do
    if [[ "$line" == "## Tests"* ]]; then
      in_tests=true
      continue
    fi
    if $in_tests; then
      [[ "$line" == "## "* ]] && break
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        test_line="${BASH_REMATCH[1]}"
        # Check for → expect pattern
        if [[ "$test_line" == *" → expect "* ]]; then
          cmd="${test_line%% → expect *}"
          expect="${test_line##* → expect }"
          run_test "custom: $cmd" "$cmd" "$expect"
        elif [[ "$test_line" == *" → "* ]]; then
          cmd="${test_line%% → *}"
          expect="${test_line##* → }"
          run_test "custom: $cmd" "$cmd" "$expect"
        else
          run_test "custom: $test_line" "$test_line"
        fi
      fi
    fi
  done < "$SWARM_DIR/tasks/${THREAD}.md"
fi

# Output
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "PASS: $PASSED/$TOTAL tests passed"
  exit 0
else
  echo "FAIL: $PASSED/$TOTAL tests passed"
  echo -e "$ERRORS"
  exit 1
fi
