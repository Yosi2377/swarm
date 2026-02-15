#!/bin/bash
# guard.sh — Guardrails: validate agent output before delivery
# Usage: guard.sh <check_type> <thread_id> [options]
# Checks: pre-send, code-review, screenshots, production-safe, full
set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX_DIR="/root/sandbox"
ACTION="${1:-help}"
THREAD="${2:-0}"
ERRORS=()
WARNINGS=()

pass() { echo "✅ PASS: $1"; }
fail() { ERRORS+=("$1"); echo "❌ FAIL: $1"; }
warn() { WARNINGS+=("$1"); echo "⚠️ WARN: $1"; }

# ─── CHECK: No production files edited directly ───
check_production_safe() {
  local SANDBOX="${1:-}"
  
  # Check recent git diffs in production dirs
  for proj in /root/BettingPlatform /root/TexasPokerGame /root/Blackjack-Game-Multiplayer; do
    if [ -d "$proj/.git" ]; then
      cd "$proj"
      UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
      if [ "$UNCOMMITTED" -gt 0 ]; then
        fail "Production project $(basename $proj) has $UNCOMMITTED uncommitted changes!"
      fi
    fi
  done
  
  # Verify sandbox exists and was used
  if [ -n "$SANDBOX" ] && [ ! -d "$SANDBOX" ]; then
    fail "Sandbox $SANDBOX doesn't exist — work may have been done on production"
  fi
}

# ─── CHECK: Screenshots taken ───
check_screenshots() {
  local THREAD="$1"
  local COUNT=$(ls /tmp/screenshot-*-${THREAD}.png /tmp/screenshot-*${THREAD}*.png 2>/dev/null | wc -l)
  COUNT=${COUNT:-0}
  
  if [ "$COUNT" -lt 1 ]; then
    warn "No screenshots found for thread $THREAD"
  else
    pass "Found $COUNT screenshots for thread $THREAD"
  fi
}

# ─── CHECK: Task file updated ───
check_task_updated() {
  local THREAD="$1"
  
  if [ -f "$SWARM_DIR/tasks/$THREAD.md" ]; then
    # Check if status was updated
    if grep -q "Status:.*done\|Status:.*completed\|✅" "$SWARM_DIR/tasks/$THREAD.md" 2>/dev/null; then
      pass "Task file $THREAD.md has completion status"
    else
      warn "Task file $THREAD.md exists but may not be marked complete"
    fi
  else
    warn "No task file found: tasks/$THREAD.md"
  fi
}

# ─── CHECK: No secrets/credentials in output ───
check_no_secrets() {
  local FILE="${1:-}"
  if [ -n "$FILE" ] && [ -f "$FILE" ]; then
    if grep -iE "(password|secret|api.?key|token|private.?key)" "$FILE" 2>/dev/null | grep -v "^#" | head -5; then
      warn "Possible secrets found in output file"
    else
      pass "No obvious secrets in output"
    fi
  fi
}

# ─── CHECK: Sandbox has committed changes ───
check_sandbox_committed() {
  local SANDBOX="${1:-}"
  if [ -n "$SANDBOX" ] && [ -d "$SANDBOX/.git" ]; then
    cd "$SANDBOX"
    UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$UNCOMMITTED" -gt 0 ]; then
      fail "Sandbox has $UNCOMMITTED uncommitted files"
    else
      pass "Sandbox changes committed"
    fi
  fi
}

# ─── CHECK: Output quality (file sizes, not empty) ───
check_output_quality() {
  local SANDBOX="${1:-}"
  if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
    # Check for empty files that were recently modified
    EMPTY=$(find "$SANDBOX" -name "*.js" -o -name "*.html" -o -name "*.css" | xargs -I{} sh -c 'test ! -s "{}" && echo "{}"' 2>/dev/null | wc -l)
    if [ "$EMPTY" -gt 0 ]; then
      warn "$EMPTY empty source files found in sandbox"
    fi
  fi
}

# ─── MAIN ───
case "$ACTION" in
  production-safe)
    SANDBOX="${3:-}"
    check_production_safe "$SANDBOX"
    ;;
    
  screenshots)
    check_screenshots "$THREAD"
    ;;
    
  task-updated)
    check_task_updated "$THREAD"
    ;;
    
  sandbox-committed)
    SANDBOX="${3:-}"
    check_sandbox_committed "$SANDBOX"
    ;;
    
  full)
    SANDBOX="${3:-}"
    echo "🛡️ Full Guardrails Check — Thread $THREAD"
    echo "=================================="
    check_production_safe "$SANDBOX"
    check_screenshots "$THREAD"
    check_task_updated "$THREAD"
    check_sandbox_committed "$SANDBOX"
    check_output_quality "$SANDBOX"
    echo "=================================="
    
    if [ ${#ERRORS[@]} -gt 0 ]; then
      echo ""
      echo "🔴 ${#ERRORS[@]} ERRORS found — DO NOT proceed to production!"
      for e in "${ERRORS[@]}"; do echo "  ❌ $e"; done
      exit 1
    elif [ ${#WARNINGS[@]} -gt 0 ]; then
      echo ""
      echo "🟡 ${#WARNINGS[@]} WARNINGS — Review before proceeding"
      for w in "${WARNINGS[@]}"; do echo "  ⚠️ $w"; done
      exit 0
    else
      echo ""
      echo "🟢 All checks passed!"
      exit 0
    fi
    ;;
    
  *)
    echo "🛡️ Guardrails — Agent Output Validation"
    echo "Usage:"
    echo "  guard.sh production-safe <thread> [sandbox_path]  — Check no production edits"
    echo "  guard.sh screenshots <thread>                     — Check screenshots exist"
    echo "  guard.sh task-updated <thread>                    — Check task file updated"
    echo "  guard.sh sandbox-committed <thread> <sandbox>     — Check sandbox committed"
    echo "  guard.sh full <thread> [sandbox_path]             — Run ALL checks"
    ;;
esac
