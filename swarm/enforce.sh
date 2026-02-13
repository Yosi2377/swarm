#!/bin/bash
# enforce.sh — Flow Enforcement for Swarm Agents
# Returns PASS or FAIL. Non-negotiable.
set -euo pipefail

SWARM_DIR="/root/.openclaw/workspace/swarm"
SANDBOX_DIR="/root/sandbox"
SEND="$SWARM_DIR/send.sh"

usage() {
  echo "Usage:"
  echo "  enforce.sh pre-work <project_path> <thread_id>  — Create sandbox + git checkpoint"
  echo "  enforce.sh post-work <thread_id>                 — Verify screenshots + commit"
  echo "  enforce.sh review <thread_id>                    — Trigger שומר review"
  echo "  enforce.sh check-sandbox                         — Verify agent is in sandbox"
  exit 1
}

[[ $# -lt 1 ]] && usage

ACTION="$1"

# ─── PRE-WORK: sandbox + checkpoint ───
if [[ "$ACTION" == "pre-work" ]]; then
  [[ $# -lt 3 ]] && { echo "FAIL: pre-work needs <project_path> <thread_id>"; exit 1; }
  PROJECT="$2"
  THREAD="$3"
  PROJECT_NAME=$(basename "$PROJECT")

  # Git checkpoint
  cd "$PROJECT"
  SAFE_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "no-git")
  echo "$SAFE_COMMIT" > "/tmp/safe_commit_${PROJECT_NAME}"
  echo "📌 Checkpoint: $SAFE_COMMIT"

  # Create sandbox
  "$SWARM_DIR/sandbox.sh" create "$PROJECT" 2>/dev/null && {
    echo "✅ Sandbox created at $SANDBOX_DIR/$PROJECT_NAME"
  } || {
    # Already exists? Check
    if [[ -d "$SANDBOX_DIR/$PROJECT_NAME" ]]; then
      echo "✅ Sandbox already exists at $SANDBOX_DIR/$PROJECT_NAME"
    else
      echo "FAIL: Could not create sandbox"
      exit 1
    fi
  }

  # Write enforcement state
  cat > "/tmp/enforce_${THREAD}.json" <<EOF
{"thread":"$THREAD","project":"$PROJECT","sandbox":"$SANDBOX_DIR/$PROJECT_NAME","safe_commit":"$SAFE_COMMIT","phase":"working","screenshots":0,"committed":false}
EOF

  echo "PASS"
  exit 0
fi

# ─── POST-WORK: check screenshots + commit ───
if [[ "$ACTION" == "post-work" ]]; then
  [[ $# -lt 2 ]] && { echo "FAIL: post-work needs <thread_id>"; exit 1; }
  THREAD="$2"
  STATE="/tmp/enforce_${THREAD}.json"
  ERRORS=()

  # Check screenshots exist
  SCREENSHOTS=$(ls /tmp/screenshot-*-${THREAD}.png 2>/dev/null | wc -l || echo 0)
  # Also check generic screenshot names
  SCREENSHOTS_ALT=$(ls /tmp/screenshot-desktop.png /tmp/screenshot-tablet.png /tmp/screenshot-mobile.png 2>/dev/null | wc -l || echo 0)
  TOTAL=$((SCREENSHOTS + SCREENSHOTS_ALT))

  if [[ "$TOTAL" -lt 3 ]]; then
    ERRORS+=("Missing screenshots ($TOTAL/3). Need desktop+tablet+mobile.")
  fi

  # Check if sandbox has uncommitted changes
  if [[ -f "$STATE" ]]; then
    SANDBOX=$(python3 -c "import json;print(json.load(open('$STATE'))['sandbox'])" 2>/dev/null || echo "")
    if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
      cd "$SANDBOX"
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        ERRORS+=("Uncommitted changes in sandbox!")
      fi
    fi
  fi

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "FAIL:"
    for e in "${ERRORS[@]}"; do echo "  ❌ $e"; done
    exit 1
  fi

  echo "PASS"
  exit 0
fi

# ─── REVIEW: trigger שומר ───
if [[ "$ACTION" == "review" ]]; then
  [[ $# -lt 2 ]] && { echo "FAIL: review needs <thread_id>"; exit 1; }
  THREAD="$2"
  STATE="/tmp/enforce_${THREAD}.json"

  if [[ -f "$STATE" ]]; then
    SANDBOX=$(python3 -c "import json;print(json.load(open('$STATE'))['sandbox'])" 2>/dev/null || echo "")
    PROJECT=$(python3 -c "import json;print(json.load(open('$STATE'))['project'])" 2>/dev/null || echo "")
  fi

  # Get diff for review
  DIFF=""
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    cd "$SANDBOX"
    DIFF=$(git diff HEAD~1 --stat 2>/dev/null || echo "no diff available")
  fi

  # Post review request to Agent Chat
  "$SEND" shomer 479 "🔒 <b>Gate 1 — Code Review נדרש</b>
📍 Thread: $THREAD
📁 Sandbox: ${SANDBOX:-unknown}

<pre>$DIFF</pre>

בדוק: רלוונטיות, שבירה, באגים, סודות, בדיקה."

  echo "PASS — Review request sent to שומר"
  exit 0
fi

# ─── CHECK-SANDBOX: verify working in sandbox ───
if [[ "$ACTION" == "check-sandbox" ]]; then
  CWD="${2:-$(pwd)}"
  if [[ "$CWD" == /root/sandbox/* ]]; then
    echo "PASS"
  else
    echo "FAIL: Working directory is $CWD — must be under /root/sandbox/"
    exit 1
  fi
  exit 0
fi

usage
