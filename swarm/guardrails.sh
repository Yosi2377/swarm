#!/bin/bash
# guardrails.sh — Safety checks before agent operations
# Usage: source guardrails.sh (agents source this at start)
# Overrides dangerous commands with safe versions

# Block raw deleteMany
alias mongo="echo '⛔ Use mongosh with guardrails instead'"

# Safe delete wrapper
safe_delete() {
  local collection="$1"
  local filter="$2"
  
  PROTECTED="agents skills posts owners comments messages"
  for p in $PROTECTED; do
    if [ "$collection" = "$p" ] && [ "$filter" = "{}" ]; then
      echo "⛔ BLOCKED: Cannot deleteMany({}) on protected collection '$collection'"
      echo "Use a specific filter or safeDeleteMany from agent-safety.js"
      return 1
    fi
  done
}

# Backup before any DB operation
pre_db_op() {
  echo "📦 Auto-backup before DB operation..."
  if [ -f "$PROJECT_DIR/scripts/pre-agent-backup.sh" ]; then
    bash "$PROJECT_DIR/scripts/pre-agent-backup.sh" 2>/dev/null
  fi
}

export -f safe_delete pre_db_op 2>/dev/null
echo "🛡️ Guardrails loaded"
