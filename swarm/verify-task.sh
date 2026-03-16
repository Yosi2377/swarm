#!/bin/bash
# verify-task.sh — Independent verification when agent reports done
# NEVER trusts agent self-report. Runs real checks.
# Usage: verify-task.sh <agent_id> <thread_id> [project_dir]
# Returns: exit 0 = PASS, exit 1 = RETRY, exit 2 = ESCALATE
# Outputs verification details to stdout (parseable)

set -euo pipefail

AGENT_ID="${1:?Usage: verify-task.sh <agent_id> <thread_id> [project_dir]}"
THREAD_ID="${2:?Missing thread_id}"
PROJECT_DIR="${3:-}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SWARM_DIR/core/tasks"
META_FILE="$TASKS_DIR/${AGENT_ID}-${THREAD_ID}.json"
CONTRACT_FILE="$TASKS_DIR/${AGENT_ID}-${THREAD_ID}.contract.json"
REPORT_FILE="$SWARM_DIR/agent-reports/${AGENT_ID}-${THREAD_ID}.json"
VERIFY_LOG="/tmp/verify-${AGENT_ID}-${THREAD_ID}.log"

# Clear previous log
> "$VERIFY_LOG"

log() { echo "$1" | tee -a "$VERIFY_LOG"; }
fail() { log "❌ FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass_check() { log "✅ PASS: $1"; PASSES=$((PASSES + 1)); }

FAILURES=0
PASSES=0
CHECKS=0
TASK_TYPE="unknown"

# --- Detect task type from contract/meta ---
if [ -f "$CONTRACT_FILE" ]; then
  TASK_TYPE=$(node -e "
    const c = require('$CONTRACT_FILE');
    const criteria = (c.acceptance_criteria || []).map(x => x.type).join(',');
    if (criteria.includes('url') || criteria.includes('ui')) console.log('ui');
    else if (criteria.includes('api') || criteria.includes('endpoint')) console.log('api');
    else if (criteria.includes('file') || criteria.includes('code')) console.log('code');
    else console.log('code');
  " 2>/dev/null || echo "code")
fi

# If no contract, infer from task description in meta
if [ "$TASK_TYPE" = "unknown" ] && [ -f "$META_FILE" ]; then
  TASK_TYPE=$(node -e "
    const m = require('$META_FILE');
    const d = (m.description || m.task || '').toLowerCase();
    if (d.match(/url|page|ui|design|css|html|frontend/)) console.log('ui');
    else if (d.match(/api|endpoint|curl|rest|graphql/)) console.log('api');
    else console.log('code');
  " 2>/dev/null || echo "code")
fi

log "🔍 Verifying ${AGENT_ID}-${THREAD_ID} (type: ${TASK_TYPE})"
log "================================================"

# =============================================================
# 1. BASIC: Check agent report exists
# =============================================================
CHECKS=$((CHECKS + 1))
if [ -f "$REPORT_FILE" ]; then
  AGENT_STATUS=$(node -e "console.log(require('$REPORT_FILE').status || 'unknown')" 2>/dev/null || echo "unknown")
  if [ "$AGENT_STATUS" = "failed" ]; then
    fail "Agent self-reported failure"
  else
    pass_check "Agent report exists (status: $AGENT_STATUS)"
  fi
else
  log "⚠️ No agent report file found — verifying independently"
fi

# =============================================================
# 2. CODE VERIFICATION — git diff, lint, tests
# =============================================================
verify_code() {
  local dir="${1:-.}"
  
  # Check if files were actually changed
  CHECKS=$((CHECKS + 1))
  if [ -d "$dir/.git" ]; then
    CHANGED=$(cd "$dir" && git diff --name-only HEAD~1 2>/dev/null | wc -l || echo "0")
    if [ "$CHANGED" -eq 0 ]; then
      CHANGED=$(cd "$dir" && git diff --name-only 2>/dev/null | wc -l || echo "0")
    fi
    if [ "$CHANGED" -eq 0 ]; then
      fail "No files changed in git"
    else
      pass_check "Git shows $CHANGED file(s) changed"
    fi
  fi

  # Run linter if available
  CHECKS=$((CHECKS + 1))
  if [ -f "$dir/package.json" ]; then
    HAS_LINT=$(node -e "const p=require('$dir/package.json'); console.log(p.scripts?.lint ? 'yes' : 'no')" 2>/dev/null || echo "no")
    if [ "$HAS_LINT" = "yes" ]; then
      if (cd "$dir" && npm run lint --silent 2>&1 | tail -20) >> "$VERIFY_LOG" 2>&1; then
        pass_check "Lint passed"
      else
        fail "Lint failed"
      fi
    else
      log "⚠️ SKIP: No lint script in package.json"
    fi
  elif [ -f "$dir/Makefile" ] && grep -q "lint" "$dir/Makefile" 2>/dev/null; then
    if (cd "$dir" && make lint 2>&1 | tail -20) >> "$VERIFY_LOG" 2>&1; then
      pass_check "Lint passed"
    else
      fail "Lint failed"
    fi
  else
    log "⚠️ SKIP: No linter found"
  fi

  # Run tests if available
  CHECKS=$((CHECKS + 1))
  if [ -f "$dir/package.json" ]; then
    HAS_TEST=$(node -e "const p=require('$dir/package.json'); console.log(p.scripts?.test && p.scripts.test !== 'echo \"Error: no test specified\" && exit 1' ? 'yes' : 'no')" 2>/dev/null || echo "no")
    if [ "$HAS_TEST" = "yes" ]; then
      if (cd "$dir" && timeout 120 npm test 2>&1 | tail -30) >> "$VERIFY_LOG" 2>&1; then
        pass_check "Tests passed"
      else
        fail "Tests failed"
      fi
    else
      log "⚠️ SKIP: No test script"
    fi
  elif [ -f "$dir/Makefile" ] && grep -q "test" "$dir/Makefile" 2>/dev/null; then
    if (cd "$dir" && timeout 120 make test 2>&1 | tail -30) >> "$VERIFY_LOG" 2>&1; then
      pass_check "Tests passed"
    else
      fail "Tests failed"
    fi
  fi

  # Check for syntax errors in changed files
  CHECKS=$((CHECKS + 1))
  if [ -d "$dir/.git" ]; then
    SYNTAX_ERRORS=0
    for f in $(cd "$dir" && git diff --name-only HEAD~1 2>/dev/null || git diff --name-only 2>/dev/null); do
      [ ! -f "$dir/$f" ] && continue
      case "$f" in
        *.js)  node --check "$dir/$f" 2>/dev/null || SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1)) ;;
        *.json) python3 -c "import json; json.load(open('$dir/$f'))" 2>/dev/null || SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1)) ;;
        *.sh)  bash -n "$dir/$f" 2>/dev/null || SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1)) ;;
        *.py)  python3 -m py_compile "$dir/$f" 2>/dev/null || SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1)) ;;
      esac
    done
    if [ "$SYNTAX_ERRORS" -gt 0 ]; then
      fail "Syntax errors in $SYNTAX_ERRORS file(s)"
    else
      pass_check "No syntax errors in changed files"
    fi
  fi
}

# =============================================================
# 3. UI VERIFICATION — URL responds, basic content checks
# =============================================================
verify_ui() {
  local url="$1"
  
  # Check URL responds
  CHECKS=$((CHECKS + 1))
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
    pass_check "URL responds with HTTP $HTTP_CODE"
  else
    fail "URL returned HTTP $HTTP_CODE"
    return
  fi

  # Check page has content
  CHECKS=$((CHECKS + 1))
  BODY_SIZE=$(curl -s --max-time 10 "$url" 2>/dev/null | wc -c)
  if [ "$BODY_SIZE" -gt 100 ]; then
    pass_check "Page has content ($BODY_SIZE bytes)"
  else
    fail "Page appears empty ($BODY_SIZE bytes)"
  fi

  # Check no error messages in body
  CHECKS=$((CHECKS + 1))
  BODY=$(curl -s --max-time 10 "$url" 2>/dev/null)
  if echo "$BODY" | grep -qi "internal server error\|502 bad gateway\|503 service\|cannot GET\|ECONNREFUSED"; then
    fail "Error message found in page body"
  else
    pass_check "No obvious errors in page"
  fi
}

# =============================================================
# 4. API VERIFICATION — endpoint responds, valid JSON
# =============================================================
verify_api() {
  local url="$1"
  
  # Check endpoint responds
  CHECKS=$((CHECKS + 1))
  HTTP_CODE=$(curl -s -o /tmp/verify-api-body.tmp -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
    pass_check "API responds with HTTP $HTTP_CODE"
  else
    fail "API returned HTTP $HTTP_CODE"
    return
  fi

  # Check valid JSON response
  CHECKS=$((CHECKS + 1))
  if python3 -c "import json; json.load(open('/tmp/verify-api-body.tmp'))" 2>/dev/null; then
    pass_check "Response is valid JSON"
  else
    # Not all APIs return JSON, just warn
    log "⚠️ Response is not JSON (may be OK for non-JSON APIs)"
  fi
}

# =============================================================
# 5. CONTRACT-BASED VERIFICATION
# =============================================================
verify_contract() {
  if [ ! -f "$CONTRACT_FILE" ]; then
    log "⚠️ No contract file — skipping contract verification"
    return
  fi

  CHECKS=$((CHECKS + 1))
  # Run the existing semantic verification as one input
  SEMANTIC_RESULT=$(bash "$SWARM_DIR/orchestrator-verify.sh" "$AGENT_ID" "$THREAD_ID" "$PROJECT_DIR" 2>/dev/null || echo '{"action":"retry","reason":"verification script failed"}')
  SEMANTIC_ACTION=$(echo "$SEMANTIC_RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.action||'unknown')" 2>/dev/null || echo "unknown")
  
  if [ "$SEMANTIC_ACTION" = "pass" ]; then
    pass_check "Contract semantic verification passed"
  else
    REASON=$(echo "$SEMANTIC_RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.reason||d.prompt||'unknown')" 2>/dev/null || echo "unknown")
    fail "Contract verification: $REASON"
  fi
}

# =============================================================
# RUN VERIFICATION BASED ON TASK TYPE
# =============================================================

# Always run contract verification
verify_contract

# Detect URL from report/contract
URL=""
if [ -f "$REPORT_FILE" ]; then
  URL=$(node -e "const r=require('$REPORT_FILE'); console.log(r.url||'')" 2>/dev/null || echo "")
fi
if [ -z "$URL" ] || [ "$URL" = "n/a" ]; then
  if [ -f "$CONTRACT_FILE" ]; then
    URL=$(node -e "
      const c=require('$CONTRACT_FILE');
      const u=(c.acceptance_criteria||[]).find(x=>x.url);
      console.log(u?.url||'');
    " 2>/dev/null || echo "")
  fi
fi

# Detect project dir
PROJ_DIR="$PROJECT_DIR"
if [ -z "$PROJ_DIR" ] && [ -f "$META_FILE" ]; then
  PROJ_DIR=$(node -e "const m=require('$META_FILE'); console.log(m.project_dir||m.projectDir||'')" 2>/dev/null || echo "")
fi

case "$TASK_TYPE" in
  code)
    if [ -n "$PROJ_DIR" ] && [ -d "$PROJ_DIR" ]; then
      verify_code "$PROJ_DIR"
    else
      log "⚠️ No project dir — limited code verification"
    fi
    ;;
  ui)
    if [ -n "$URL" ]; then
      verify_ui "$URL"
    else
      log "⚠️ No URL found for UI verification"
    fi
    # Also verify code if project dir available
    if [ -n "$PROJ_DIR" ] && [ -d "$PROJ_DIR" ]; then
      verify_code "$PROJ_DIR"
    fi
    ;;
  api)
    if [ -n "$URL" ]; then
      verify_api "$URL"
    else
      log "⚠️ No URL found for API verification"
    fi
    if [ -n "$PROJ_DIR" ] && [ -d "$PROJ_DIR" ]; then
      verify_code "$PROJ_DIR"
    fi
    ;;
esac

# =============================================================
# VERDICT
# =============================================================
log ""
log "================================================"
log "📊 Results: $PASSES passed, $FAILURES failed out of $CHECKS checks"

# Save verification result
mkdir -p "$SWARM_DIR/learning/episodes"
cat > "/tmp/verify-result-${AGENT_ID}-${THREAD_ID}.json" <<EOF
{
  "agent": "$AGENT_ID",
  "thread": "$THREAD_ID",
  "task_type": "$TASK_TYPE",
  "passes": $PASSES,
  "failures": $FAILURES,
  "checks": $CHECKS,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "log_file": "$VERIFY_LOG"
}
EOF

if [ "$FAILURES" -eq 0 ]; then
  log "✅ VERIFIED PASS"
  # Record success
  bash "$SWARM_DIR/learn.sh" score "$AGENT_ID" success "task-$THREAD_ID" 2>/dev/null || true
  exit 0
else
  # Check retry count from state
  RETRY_COUNT=0
  if [ -f "$META_FILE" ]; then
    RETRY_COUNT=$(node -e "
      const m=require('$META_FILE');
      console.log(m.task_state?.retryCount || m.retries || 0);
    " 2>/dev/null || echo "0")
  fi

  if [ "$RETRY_COUNT" -ge 3 ]; then
    log "🚨 ESCALATE — $RETRY_COUNT retries exhausted"
    bash "$SWARM_DIR/learn.sh" score "$AGENT_ID" fail "task-$THREAD_ID (escalated after $RETRY_COUNT retries)" 2>/dev/null || true
    exit 2
  else
    log "🔄 RETRY NEEDED (attempt $((RETRY_COUNT + 1))/3)"
    exit 1
  fi
fi
