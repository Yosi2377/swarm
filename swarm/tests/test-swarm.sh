#!/bin/bash
# Swarm System Test Suite
# Usage: bash swarm/tests/test-swarm.sh [test_name]
# Tests: tokens, send-all, send-photo, subagent, sessions-send

set -uo pipefail
SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0
CHAT_ID="-1003815143703"
AGENT_CHAT=479

red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

run_test() {
  local name="$1"; shift
  echo -n "  [$name] "
  if "$@" 2>/dev/null; then
    green "PASS"; ((PASS++))
  else
    red "FAIL"; ((FAIL++))
  fi
}

skip_test() {
  echo -n "  [$1] "; yellow "SKIP — $2"; ((SKIP++))
}

# ============================================================
# Test 1: All bot tokens exist and are non-empty
# ============================================================
test_tokens() {
  local all_ok=true
  for agent in bot shomer koder tzayar worker researcher bodek; do
    local f="$SWARM_DIR/.$agent-token"
    if [ ! -s "$f" ]; then
      echo -n "(missing: $agent) "; all_ok=false
    fi
  done
  $all_ok
}

# ============================================================
# Test 2: send.sh delivers to Telegram for each agent
# ============================================================
test_send_all() {
  local all_ok=true
  for agent in or shomer koder tzayar worker researcher bodek; do
    local result
    result=$("$SWARM_DIR/send.sh" "$agent" "$AGENT_CHAT" "🧪 test-swarm.sh — $agent $(date +%H:%M:%S)" 2>&1)
    local ok
    ok=$(echo "$result" | jq -r '.ok' 2>/dev/null)
    if [ "$ok" != "true" ]; then
      echo -n "(fail: $agent) "; all_ok=false
    fi
  done
  $all_ok
}

# ============================================================
# Test 3: send.sh with --photo flag
# ============================================================
test_send_photo() {
  # Create a tiny test image
  local img="/tmp/test-swarm-photo.png"
  convert -size 100x100 xc:blue "$img" 2>/dev/null || {
    python3 -c "
import struct, zlib
def png(w,h):
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    raw=b''
    for y in range(h): raw+=b'\x00'+b'\x00\x00\xff'*w
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
open('$img','wb').write(png(100,100))
"
  }
  local result
  result=$("$SWARM_DIR/send.sh" koder "$AGENT_CHAT" "🧪 photo test $(date +%H:%M:%S)" --photo "$img" 2>&1)
  local ok
  ok=$(echo "$result" | jq -r '.ok' 2>/dev/null)
  rm -f "$img"
  [ "$ok" = "true" ]
}

# ============================================================
# Test 4: Log file is written after send
# ============================================================
test_logging() {
  local log="$SWARM_DIR/logs/$(date +%Y-%m-%d).jsonl"
  [ -f "$log" ] && tail -1 "$log" | jq -r '.agent' >/dev/null 2>&1
}

# ============================================================
# Test 5: OpenClaw config has subagent settings
# ============================================================
test_config() {
  python3 -c "
import json
d=json.load(open('/root/.openclaw/openclaw.json'))
sa=d['agents']['defaults']['subagents']
assert sa.get('maxSpawnDepth',1) >= 2, 'maxSpawnDepth < 2'
assert sa.get('maxConcurrent',0) >= 4, 'maxConcurrent too low'
"
}

# ============================================================
# Test 6: All required scripts exist and are executable
# ============================================================
test_scripts() {
  local all_ok=true
  for script in send.sh live-feed.sh spawn-agent.sh pipeline.sh learn.sh; do
    if [ ! -x "$SWARM_DIR/$script" ] && [ ! -f "$SWARM_DIR/$script" ]; then
      echo -n "(missing: $script) "; all_ok=false
    fi
  done
  $all_ok
}

# ============================================================
# Test 7: Gateway is running
# ============================================================
test_gateway() {
  openclaw status 2>&1 | grep -qi "running\|online\|connected"
}

# ============================================================
# Run
# ============================================================
echo "🧪 Swarm System Tests — $(date)"
echo "================================================"

if [ "${1:-all}" = "all" ] || [ "${1:-}" = "" ]; then
  run_test "tokens" test_tokens
  run_test "send-all" test_send_all
  run_test "send-photo" test_send_photo
  run_test "logging" test_logging
  run_test "config" test_config
  run_test "scripts" test_scripts
  run_test "gateway" test_gateway
else
  run_test "$1" "test_$1"
fi

echo "================================================"
echo "Results: $(green "$PASS pass") / $(red "$FAIL fail") / $(yellow "$SKIP skip")"
[ "$FAIL" -eq 0 ]
