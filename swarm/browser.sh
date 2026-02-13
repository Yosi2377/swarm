#!/bin/bash
# browser.sh — CLI for persistent Puppeteer browser sessions
# Usage: browser.sh [--session=ID] <command> [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/browser-server.js"
PORT="${BROWSER_SERVER_PORT:-9222}"
URL="http://127.0.0.1:$PORT"
SESSION="default"
PIDFILE="/tmp/browser-server.pid"

# Parse --session flag
while [[ "$1" == --session=* ]]; do
  SESSION="${1#--session=}"
  shift
done

ACTION="$1"
shift

ensure_server() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    return 0
  fi
  echo "Starting browser-server..."
  nohup node "$SERVER_SCRIPT" > /tmp/browser-server.log 2>&1 &
  echo $! > "$PIDFILE"
  # Wait for server
  for i in $(seq 1 30); do
    curl -s "$URL" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  echo "ERROR: Server failed to start. Check /tmp/browser-server.log"
  exit 1
}

send_cmd() {
  local json="$1"
  local result
  result=$(curl -s -X POST "$URL" -H 'Content-Type: application/json' -d "$json" 2>&1)
  if [ $? -ne 0 ]; then
    echo "ERROR: Cannot connect to browser-server"
    exit 1
  fi
  
  local ok=$(echo "$result" | jq -r '.ok' 2>/dev/null)
  local msg=$(echo "$result" | jq -r '.msg // empty' 2>/dev/null)
  local screenshot=$(echo "$result" | jq -r '.screenshot // empty' 2>/dev/null)
  
  if [ "$ok" = "true" ]; then
    [ -n "$msg" ] && echo "$msg"
    [ -n "$screenshot" ] && echo "SCREENSHOT: $screenshot"
  else
    echo "ERROR: $msg"
    exit 1
  fi
}

build_json() {
  local action="$1"
  shift
  local args_json="[]"
  if [ $# -gt 0 ]; then
    args_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
  fi
  echo "{\"action\":\"$action\",\"session\":\"$SESSION\",\"args\":$args_json}"
}

case "$ACTION" in
  start)
    ensure_server
    send_cmd "$(build_json start "$@")"
    ;;
  goto)
    ensure_server
    send_cmd "$(build_json goto "$@")"
    ;;
  login)
    ensure_server
    send_cmd "$(build_json login "$@")"
    ;;
  click)
    ensure_server
    send_cmd "$(build_json click "$@")"
    ;;
  type)
    ensure_server
    send_cmd "$(build_json type "$@")"
    ;;
  wait)
    ensure_server
    send_cmd "$(build_json wait "$@")"
    ;;
  screenshot)
    ensure_server
    send_cmd "$(build_json screenshot "$@")"
    ;;
  scroll)
    ensure_server
    send_cmd "$(build_json scroll "$@")"
    ;;
  text)
    ensure_server
    send_cmd "$(build_json text "$@")"
    ;;
  exists)
    ensure_server
    send_cmd "$(build_json exists "$@")"
    ;;
  eval)
    ensure_server
    send_cmd "$(build_json eval "$@")"
    ;;
  stop)
    send_cmd "$(build_json stop)" 2>/dev/null
    ;;
  stop-all)
    send_cmd "$(build_json stop-all)" 2>/dev/null
    # Kill server
    [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null && rm -f "$PIDFILE"
    echo "Server stopped"
    ;;
  *)
    cat <<'EOF'
browser.sh — Persistent headless browser for agents

Usage: browser.sh [--session=ID] <command> [args...]

Commands:
  start [width height]          Launch browser (default 1280x720)
  goto URL                      Navigate to URL + screenshot
  login URL user pass [uSel pSel sSel]  Login flow + screenshot
  click SELECTOR                Click element + screenshot
  type SELECTOR TEXT            Type text + screenshot
  wait SECONDS                  Wait + screenshot
  screenshot [name]             Take screenshot
  scroll [pixels]               Scroll down + screenshot
  text SELECTOR                 Get element text
  exists SELECTOR               Check if element exists
  eval CODE                     Run JS in page
  stop                          Close session
  stop-all                      Close all sessions + server

Multi-session: browser.sh --session=p1 goto http://...
Screenshots saved to /tmp/browser-*.png
EOF
    ;;
esac
