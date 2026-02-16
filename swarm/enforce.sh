#!/bin/bash
# enforce.sh — Rule enforcement for swarm agents
# Commands: pre-work, post-work, review, check-sandbox, pre-deploy

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CMD="${1:-help}"
THREAD="${2:-}"
FAILURES=0

fail() { echo -e "${RED}❌ FAIL: $1${NC}"; ((FAILURES++)); }
pass() { echo -e "${GREEN}✅ PASS: $1${NC}"; }

case "$CMD" in
  pre-work)
    # Before starting any task
    [[ -n "$THREAD" ]] && pass "Thread ID provided: $THREAD" || fail "No thread ID — must work in a topic"
    
    # Check sandbox exists for betting
    [[ -d "/root/sandbox/BettingPlatform" ]] && pass "Betting sandbox exists" || fail "No betting sandbox"
    
    # Check production is locked
    if ! touch /root/BettingPlatform/backend/public/.locktest 2>/dev/null; then
      pass "Production is locked"
    else
      rm -f /root/BettingPlatform/backend/public/.locktest
      fail "Production is UNLOCKED — run: prod-lock.sh lock"
    fi
    ;;
    
  post-work)
    # After completing work, before requesting deploy
    [[ -n "$THREAD" ]] || fail "No thread ID"
    
    # Check sandbox is running
    for port in 9089 9088 9000; do
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null || echo "000")
      if [[ "$STATUS" == "200" ]]; then
        pass "Sandbox on port $port responding"
      fi
    done
    
    # Check screenshots exist for this thread
    SHOTS=$(find /tmp -name "*${THREAD}*" -newer /tmp -mmin -30 2>/dev/null | wc -l)
    [[ "$SHOTS" -gt 0 ]] && pass "Screenshots found for thread $THREAD" || fail "No recent screenshots for thread $THREAD"
    ;;
    
  review)
    # Pre-deploy review
    # Check production is locked
    if ! touch /root/BettingPlatform/backend/public/.locktest 2>/dev/null; then
      pass "Production locked"
    else
      rm -f /root/BettingPlatform/backend/public/.locktest
      fail "Production UNLOCKED"
    fi
    
    # Check no direct production changes (uncommitted)
    for proj in /root/BettingPlatform /root/TexasPokerGame /root/Blackjack-Game-Multiplayer; do
      if [[ -d "$proj/.git" ]]; then
        DIRTY=$(cd "$proj" && git status --porcelain 2>/dev/null | wc -l)
        [[ "$DIRTY" -eq 0 ]] && pass "$(basename $proj) clean" || fail "$(basename $proj) has uncommitted changes"
      fi
    done
    ;;
    
  check-sandbox)
    # Verify sandbox is working
    echo -e "${YELLOW}Checking sandbox services...${NC}"
    for pair in "9089:betting" "9088:poker" "9000:blackjack"; do
      IFS=: read port name <<< "$pair"
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null || echo "000")
      [[ "$STATUS" == "200" ]] && pass "$name sandbox (port $port)" || echo -e "${YELLOW}⚠️ $name sandbox not running (port $port)${NC}"
    done
    ;;

  *)
    echo "Usage: enforce.sh <pre-work|post-work|review|check-sandbox> [thread_id]"
    exit 1
    ;;
esac

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo -e "${RED}💀 $FAILURES check(s) failed${NC}"
  exit 1
else
  echo -e "${GREEN}🎉 All checks passed${NC}"
  exit 0
fi
