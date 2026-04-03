#!/bin/bash
# Swarm Send v3 — transport-aware delivery (Telegram legacy + IRC jobs)
# Usage: ./send.sh <agent_id> <thread_or_job_id> <message> [--photo path]

set -euo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_ID="${1:-}"
THREAD_ID="${2:-}"
MESSAGE="${3:-}"
PHOTO_FLAG="${4:-}"
PHOTO_PATH="${5:-}"

if [ -z "$AGENT_ID" ] || [ -z "$THREAD_ID" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_id> <thread_or_job_id> <message> [--photo path]"
  echo "Agents: or, shomer, koder, tzayar, worker, researcher, bodek, data, debugger, docker, front, back, tester, refactor, monitor, optimizer, integrator"
  exit 1
fi

TRANSPORT=$(python3 - <<PY
import json
from pathlib import Path
p = Path("$SWARM_DIR/runtime.json")
if not p.exists():
    print("telegram")
else:
    print(json.loads(p.read_text()).get("transport", "telegram"))
PY
)

OPS_CHANNEL=$(python3 - <<PY
import json
from pathlib import Path
p = Path("$SWARM_DIR/runtime.json")
if not p.exists():
    print("#myops")
else:
    cfg = json.loads(p.read_text())
    print(cfg.get("irc", {}).get("opsChannel", "#myops"))
PY
)

is_done_message() {
  echo "$1" | grep -qiE '✅|סיימתי|הושלמה|done|finished|מוכן'
}

log_result() {
  local ok="$1"
  local msg_id="$2"
  local transport_name="$3"
  local target_name="$4"
  local log_dir="$SWARM_DIR/logs"
  mkdir -p "$log_dir"
  local log_file="$log_dir/$(date +%Y-%m-%d).jsonl"
  jq -cn \
    --arg ts "$(date -Iseconds)" \
    --arg agent "$AGENT_ID" \
    --arg thread "$THREAD_ID" \
    --arg msg "$MESSAGE" \
    --arg msg_id "$msg_id" \
    --arg ok "$ok" \
    --arg transport "$transport_name" \
    --arg target "$target_name" \
    '{timestamp: $ts, agent: $agent, thread: $thread, message: $msg, message_id: $msg_id, ok: $ok, transport: $transport, target: $target}' >> "$log_file"
}

create_done_marker() {
  mkdir -p /tmp/agent-done
  local marker_msg
  marker_msg=$(echo "$MESSAGE" | head -1 | cut -c1-120 | sed 's/["\\]//g')
  echo "{\"thread\":\"$THREAD_ID\",\"status\":\"success\",\"message\":\"$marker_msg\",\"agent\":\"$AGENT_ID\"}" > "/tmp/agent-done/$(date +%s)-${AGENT_ID}.json" 2>/dev/null
}

if [ "$TRANSPORT" = "irc" ] || echo "$THREAD_ID" | grep -q '^job-'; then
  RAW_CHANNEL=""
  JOB_ID=""
  case "$THREAD_ID" in
    479|agent-chat|\#agent-chat)
      RAW_CHANNEL="#agent-chat"
      ;;
    \#*)
      RAW_CHANNEL="$THREAD_ID"
      ;;
    *)
      JOB_ID="$THREAD_ID"
      TARGET_CHANNEL=$(node "$SWARM_DIR/core/job-store.js" channel "$JOB_ID" 2>/dev/null)
      if [ -z "$TARGET_CHANNEL" ]; then
        echo "ERROR: Unknown job/channel for $JOB_ID" >&2
        exit 1
      fi
      ;;
  esac

  TARGET_CHANNEL="${RAW_CHANNEL:-$TARGET_CHANNEL}"

  # Ensure the sending IRC account is actually joined + allowlisted for this
  # channel. Main Or account uses the top-level IRC config; the rest use
  # per-account IRC identities.
  if [ -n "$JOB_ID" ]; then
    FINAL_MESSAGE="[$JOB_ID] $MESSAGE"
  else
    FINAL_MESSAGE="$MESSAGE"
  fi
  if [ "$PHOTO_FLAG" = "--photo" ] && [ -n "$PHOTO_PATH" ] && [ -f "$PHOTO_PATH" ]; then
    FINAL_MESSAGE="$FINAL_MESSAGE\n[attachment omitted in IRC: $(basename "$PHOTO_PATH")]"
  fi

  set +e
  if [ "$AGENT_ID" = "or" ]; then
    python3 "$SWARM_DIR/irc-ensure-account-channel.py" main "$TARGET_CHANNEL" >/dev/null 2>&1 || true
    RESULT=$(openclaw message send --channel irc --target "$TARGET_CHANNEL" --message "$FINAL_MESSAGE" --json 2>&1)
    STATUS=$?
  else
    python3 "$SWARM_DIR/irc-agent-hub.py" ensure-start >/dev/null 2>&1 || true
    RESULT=$(python3 "$SWARM_DIR/irc-agent-hub.py" send --agent "$AGENT_ID" --channel "$TARGET_CHANNEL" --message "$FINAL_MESSAGE" 2>&1)
    STATUS=$?
  fi
  set -e

  MSG_ID=$(echo "$RESULT" | jq -r '.messageId // .message_id // .id // empty' 2>/dev/null)
  [ -n "$MSG_ID" ] || MSG_ID="irc"

  if [ $STATUS -ne 0 ]; then
    log_result "false" "$MSG_ID" "irc" "$TARGET_CHANNEL"
    echo "$RESULT"
    exit $STATUS
  fi

  if [ -n "$JOB_ID" ]; then
    node "$SWARM_DIR/core/job-store.js" event "$JOB_ID" "message" "$MESSAGE" "$AGENT_ID" >/dev/null 2>&1 || true
  fi
  log_result "true" "$MSG_ID" "irc" "$TARGET_CHANNEL"

  if [ -n "$JOB_ID" ] && is_done_message "$MESSAGE"; then
    node "$SWARM_DIR/core/job-store.js" close "$JOB_ID" "$MESSAGE" >/dev/null 2>&1 || true
    if [ "$TARGET_CHANNEL" != "$OPS_CHANNEL" ]; then
      if [ "$AGENT_ID" = "or" ]; then
        openclaw message send --channel irc --target "$OPS_CHANNEL" --message "[$JOB_ID] ✅ סיכום סופי מ-$TARGET_CHANNEL: $MESSAGE" >/dev/null 2>&1 || true
      else
        python3 "$SWARM_DIR/irc-agent-hub.py" send --agent "$AGENT_ID" --channel "$OPS_CHANNEL" --message "[$JOB_ID] ✅ סיכום סופי מ-$TARGET_CHANNEL: $MESSAGE" >/dev/null 2>&1 || true
      fi
    fi
    create_done_marker
  fi

  echo "$RESULT"
  exit 0
fi

# Telegram legacy mode
case "$AGENT_ID" in
  or)      TOKEN_FILE="$SWARM_DIR/.bot-token" ;;
  shomer)  TOKEN_FILE="$SWARM_DIR/.shomer-token" ;;
  koder)   TOKEN_FILE="$SWARM_DIR/.koder-token" ;;
  tzayar)  TOKEN_FILE="$SWARM_DIR/.tzayar-token" ;;
  worker)     TOKEN_FILE="$SWARM_DIR/.worker-token" ;;
  researcher) TOKEN_FILE="$SWARM_DIR/.researcher-token" ;;
  bodek)      TOKEN_FILE="$SWARM_DIR/.bodek-token" ;;
  data)       TOKEN_FILE="$SWARM_DIR/.data-token" ;;
  debugger)   TOKEN_FILE="$SWARM_DIR/.debugger-token" ;;
  docker)     TOKEN_FILE="$SWARM_DIR/.docker-token" ;;
  front)      TOKEN_FILE="$SWARM_DIR/.front-token" ;;
  back)       TOKEN_FILE="$SWARM_DIR/.back-token" ;;
  tester)     TOKEN_FILE="$SWARM_DIR/.tester-token" ;;
  refactor)   TOKEN_FILE="$SWARM_DIR/.refactor-token" ;;
  monitor)    TOKEN_FILE="$SWARM_DIR/.monitor-token" ;;
  optimizer)  TOKEN_FILE="$SWARM_DIR/.optimizer-token" ;;
  integrator) TOKEN_FILE="$SWARM_DIR/.integrator-token" ;;
  *)          echo "Unknown agent: $AGENT_ID"; exit 1 ;;
esac

if [ ! -f "$TOKEN_FILE" ]; then
  TOKEN_FILE="$SWARM_DIR/.bot-token"
fi
TOKEN=$(cat "$TOKEN_FILE")
CHAT_ID="-1003815143703"

THREAD_FORM_ARGS=()
THREAD_JSON_EXTRA=""
if [ "$THREAD_ID" != "1" ]; then
  THREAD_FORM_ARGS=(-F "message_thread_id=$THREAD_ID")
  THREAD_JSON_EXTRA=", \"message_thread_id\": $THREAD_ID"
fi

send_msg() {
  if [ "$PHOTO_FLAG" = "--photo" ] && [ -n "$PHOTO_PATH" ] && [ -f "$PHOTO_PATH" ]; then
    curl -s "https://api.telegram.org/bot$TOKEN/sendPhoto" \
      -F "chat_id=$CHAT_ID" \
      "${THREAD_FORM_ARGS[@]}" \
      -F "photo=@$PHOTO_PATH" \
      -F "caption=$MESSAGE" \
      -F "parse_mode=HTML"
  else
    curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\": \"$CHAT_ID\"$THREAD_JSON_EXTRA, \"text\": $(echo "$MESSAGE" | jq -Rs .), \"parse_mode\": \"HTML\"}"
  fi
}

RESULT=$(send_msg)
OK=$(echo "$RESULT" | jq -r '.ok')
if [ "$OK" != "true" ]; then
  sleep 2
  RESULT=$(send_msg)
fi

MSG_ID=$(echo "$RESULT" | jq -r '.result.message_id // "error"')
OK=$(echo "$RESULT" | jq -r '.ok')
log_result "$OK" "$MSG_ID" "telegram" "$CHAT_ID"

if is_done_message "$MESSAGE"; then
  create_done_marker
fi

echo "$RESULT"
