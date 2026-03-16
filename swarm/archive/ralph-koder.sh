#!/usr/bin/env bash
#
# ralph-koder.sh — Ralph Loop adapted for swarm koder tasks
# Runs a coding agent in a loop with testing & verification
#
# Usage: ralph-koder.sh <task-id> <thread-id> <project-dir> [max-iterations]
#
# Example:
#   ralph-koder.sh task-5388 5388 /root/sandbox/BettingPlatform 10
#
set -euo pipefail

TASK_ID="${1:?Usage: ralph-koder.sh <task-id> <thread-id> <project-dir> [max-iters]}"
THREAD_ID="${2:?Missing thread-id}"
PROJECT_DIR="${3:?Missing project directory}"
MAX_ITERS="${4:-10}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$PROJECT_DIR/.ralph/$TASK_ID"
LOG_FILE="$RALPH_DIR/ralph.log"
ITERATIONS_FILE="$RALPH_DIR/iterations.jsonl"
PLAN_FILE="$PROJECT_DIR/IMPLEMENTATION_PLAN.md"
PROMPT_FILE="$PROJECT_DIR/PROMPT.md"

# Ensure dirs
mkdir -p "$RALPH_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

send_status() {
  local msg="$1"
  bash "$SWARM_DIR/send.sh" koder "$THREAD_ID" "$msg" 2>/dev/null || true
}

notify_orchestrator() {
  local prefix="$1"
  local message="$2"
  
  # Write notification file
  cat > "$RALPH_DIR/pending-notification.txt" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "task_id": "$TASK_ID",
  "thread_id": "$THREAD_ID",
  "project": "$PROJECT_DIR",
  "prefix": "$prefix",
  "message": "$message",
  "iteration": ${CURRENT_ITER:-0},
  "max_iterations": $MAX_ITERS,
  "status": "pending"
}
EOF

  # Notify OpenClaw
  if command -v openclaw &>/dev/null; then
    openclaw cron add \
      --name "ralph-${TASK_ID}-notify" \
      --at "3s" \
      --session main \
      --system-event "[Ralph:${TASK_ID}] ${prefix}: ${message}" \
      --wake now \
      --delete-after-run >/dev/null 2>&1 && \
      sed -i 's/"status": "pending"/"status": "delivered"/' "$RALPH_DIR/pending-notification.txt" 2>/dev/null || true
  fi
}

# Check prerequisites
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo -e "${RED}❌ Project directory not found: $PROJECT_DIR${NC}"
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo -e "${RED}❌ PROMPT.md not found in $PROJECT_DIR${NC}"
  echo "Create it with the task description first."
  exit 1
fi

cd "$PROJECT_DIR"

log "${BLUE}🐺 Ralph-Koder starting${NC}"
log "   Task: $TASK_ID (thread $THREAD_ID)"
log "   Project: $PROJECT_DIR"
log "   Max iterations: $MAX_ITERS"

send_status "🐺 <b>Ralph Loop started</b>
Task: $TASK_ID
Iterations: max $MAX_ITERS
Project: $(basename "$PROJECT_DIR")"

# Detect test command from AGENTS.md or PROMPT.md
TEST_CMD=""
if [[ -f "AGENTS.md" ]]; then
  TEST_CMD=$(grep -A1 "test_command\|TEST_CMD\|verify:" AGENTS.md 2>/dev/null | tail -1 | sed 's/^[- ]*//' || true)
fi

# Main loop
for i in $(seq 1 "$MAX_ITERS"); do
  CURRENT_ITER=$i
  ITER_START=$(date +%s)
  
  log "${BLUE}=== Iteration $i/$MAX_ITERS ===${NC}"
  send_status "🔄 <b>Iteration $i/$MAX_ITERS</b>"

  # Run agent with fresh session
  AGENT_OUTPUT=""
  AGENT_EXIT=0
  
  if command -v codex &>/dev/null; then
    AGENT_OUTPUT=$(codex exec -s workspace-write "$(cat PROMPT.md)" 2>&1) || AGENT_EXIT=$?
  elif command -v claude &>/dev/null; then
    AGENT_OUTPUT=$(claude --print --dangerously-skip-permissions "$(cat PROMPT.md)" 2>&1) || AGENT_EXIT=$?
  else
    log "${RED}❌ No coding CLI found (codex/claude)${NC}"
    notify_orchestrator "ERROR" "No coding CLI available"
    exit 1
  fi

  # Log output
  echo "$AGENT_OUTPUT" >> "$LOG_FILE"

  if ((AGENT_EXIT != 0)); then
    log "${YELLOW}⚠️ Agent exited with code $AGENT_EXIT${NC}"
    send_status "⚠️ Iteration $i: agent error (exit $AGENT_EXIT)"
    notify_orchestrator "ERROR" "Agent crashed at iteration $i/$MAX_ITERS (exit $AGENT_EXIT)"
    sleep 5
    continue
  fi

  # Run tests if configured
  if [[ -n "$TEST_CMD" ]]; then
    log "🧪 Running tests: $TEST_CMD"
    TEST_OUTPUT=""
    TEST_EXIT=0
    TEST_OUTPUT=$(bash -lc "$TEST_CMD" 2>&1) || TEST_EXIT=$?
    
    if ((TEST_EXIT == 0)); then
      log "${GREEN}✅ Tests passed${NC}"
      send_status "✅ Iteration $i: tests passed"
    else
      log "${YELLOW}❌ Tests failed${NC}"
      echo "$TEST_OUTPUT" >> "$LOG_FILE"
      send_status "❌ Iteration $i: tests failed
<pre>$(echo "$TEST_OUTPUT" | tail -10)</pre>"
      # Don't notify on first failure — agent gets to retry
      if ((i > 2)); then
        notify_orchestrator "ERROR" "Tests failing since iteration $i"
      fi
    fi
  fi

  # Take screenshot for visual verification (if browser test configured)
  if grep -q "VERIFY_URL" AGENTS.md 2>/dev/null; then
    VERIFY_URL=$(grep "VERIFY_URL" AGENTS.md | head -1 | sed 's/.*VERIFY_URL[=: ]*//')
    log "📸 Visual verification: $VERIFY_URL"
    send_status "📸 Taking verification screenshot..."
    # Screenshot will be done by the orchestrator via sessions_send
  fi

  # Check completion
  if [[ -f "$PLAN_FILE" ]] && grep -Fq "STATUS: COMPLETE" "$PLAN_FILE" 2>/dev/null; then
    ITER_END=$(date +%s)
    DURATION=$((ITER_END - ITER_START))
    log "${GREEN}✅ All tasks complete after $i iterations ($DURATION sec)${NC}"
    send_status "🎉 <b>All tasks complete!</b>
Iterations: $i/$MAX_ITERS
Total time: ${DURATION}s"
    notify_orchestrator "DONE" "All tasks complete after $i iterations"
    
    # Log iteration
    echo "{\"iteration\":$i,\"status\":\"done\",\"duration\":$DURATION}" >> "$ITERATIONS_FILE"
    exit 0
  fi

  # Check if agent says PLANNING_COMPLETE
  if [[ -f "$PLAN_FILE" ]] && grep -Fq "STATUS: PLANNING_COMPLETE" "$PLAN_FILE" 2>/dev/null; then
    log "${GREEN}📋 Planning complete${NC}"
    send_status "📋 <b>Planning complete</b> — switching to BUILD mode"
    notify_orchestrator "PLANNING_COMPLETE" "Plan ready, starting build phase"
    
    # Switch to building prompt if available
    if [[ -f "PROMPT-BUILDING.md" ]]; then
      cp PROMPT-BUILDING.md PROMPT.md
      log "Switched to PROMPT-BUILDING.md"
    fi
  fi

  # Check for DECISION/BLOCKED markers
  if [[ -f "$RALPH_DIR/pending-notification.txt" ]]; then
    PREFIX=$(python3 -c "import json; print(json.load(open('$RALPH_DIR/pending-notification.txt'))['prefix'])" 2>/dev/null || echo "")
    if [[ "$PREFIX" == "DECISION" || "$PREFIX" == "BLOCKED" ]]; then
      log "${YELLOW}⏸️ Agent needs input: $PREFIX${NC}"
      send_status "⏸️ <b>Waiting for input</b> — agent is blocked"
      # Don't continue — wait for inject
      sleep 30
    fi
  fi

  ITER_END=$(date +%s)
  DURATION=$((ITER_END - ITER_START))
  echo "{\"iteration\":$i,\"status\":\"running\",\"duration\":$DURATION}" >> "$ITERATIONS_FILE"
  
  # Brief pause between iterations
  sleep 2
done

log "${RED}❌ Max iterations ($MAX_ITERS) reached without completion${NC}"
send_status "⚠️ <b>Max iterations reached</b> ($MAX_ITERS) — task incomplete"
notify_orchestrator "BLOCKED" "Max iterations ($MAX_ITERS) reached without completion"
exit 1
