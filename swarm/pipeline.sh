#!/bin/bash
# Pipeline — Task step manager for swarm agents
# Usage: pipeline.sh <command> <task-id> [args...]

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SWARM_DIR/tasks"
VERIFY_DIR="$SWARM_DIR/verify"
STEPS=("sandbox" "verify_sandbox" "review" "deploy" "verify_prod" "done")

mkdir -p "$TASKS_DIR"

usage() {
  cat <<EOF
Usage: $0 <command> <task-id> [args...]

Commands:
  init <task-id> <thread-id> [agent-id]  — Create new task pipeline
  advance <task-id>                       — Advance to next step
  status <task-id>                        — Show current status
  verify <task-id> [url]                  — Run verify for current step
  review <task-id>                        — Post review request
  approve <task-id>                       — Approve review
  reject <task-id> "reason"              — Reject back to sandbox
  done-step <task-id>                     — Mark current step as done

Steps: sandbox → verify_sandbox → review → deploy → verify_prod → done
EOF
  exit 1
}

task_file() { echo "$TASKS_DIR/${1}.pipeline.json"; }

get_field() { python3 -c "import json;d=json.load(open('$1'));print(d.get('$2',''))" 2>/dev/null; }
set_field() {
  python3 -c "
import json,sys
f='$1'
d=json.load(open(f))
d['$2']=$3
json.dump(d,open(f,'w'),indent=2)
" 2>/dev/null
}

current_step_index() {
  local step=$(get_field "$1" "current_step")
  for i in "${!STEPS[@]}"; do
    [ "${STEPS[$i]}" = "$step" ] && echo "$i" && return
  done
  echo "-1"
}

CMD="$1"; TASK_ID="$2"
[ -z "$CMD" ] && usage

case "$CMD" in
  init)
    THREAD_ID="$3"; AGENT_ID="${4:-unknown}"
    [ -z "$TASK_ID" ] || [ -z "$THREAD_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    cat > "$TF" <<EOJSON
{
  "task_id": "$TASK_ID",
  "thread_id": "$THREAD_ID",
  "agent_id": "$AGENT_ID",
  "current_step": "sandbox",
  "current_status": "active",
  "created_at": "$(date -Is)",
  "updated_at": "$(date -Is)",
  "restarts": 0,
  "steps": {
    "sandbox": "active",
    "verify_sandbox": "pending",
    "review": "pending",
    "deploy": "pending",
    "verify_prod": "pending",
    "done": "pending"
  },
  "history": ["$(date -Is) — init: sandbox active"]
}
EOJSON
    echo "✅ Pipeline initialized for task $TASK_ID (thread $THREAD_ID, agent $AGENT_ID)"
    echo "Current step: sandbox (active)"
    # Create/switch to task branch
    "$SWARM_DIR/branch-task.sh" "$TASK_ID" "$AGENT_ID" 2>&1 || echo "⚠️ Branch creation skipped"
    ;;

  status)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    STEP=$(get_field "$TF" "current_step")
    STATUS=$(get_field "$TF" "current_status")
    AGENT=$(get_field "$TF" "agent_id")
    THREAD=$(get_field "$TF" "thread_id")
    echo "📋 Task: $TASK_ID | Agent: $AGENT | Thread: $THREAD"
    echo "📍 Step: $STEP ($STATUS)"
    echo "Steps:"
    for s in "${STEPS[@]}"; do
      S_STATUS=$(python3 -c "import json;d=json.load(open('$TF'));print(d['steps']['$s'])" 2>/dev/null)
      case "$S_STATUS" in
        done)    ICON="✅" ;;
        active)  ICON="🔄" ;;
        failed)  ICON="❌" ;;
        *)       ICON="⬜" ;;
      esac
      echo "  $ICON $s: $S_STATUS"
    done
    ;;

  done-step)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    STEP=$(get_field "$TF" "current_step")
    set_field "$TF" "steps" "dict(json.load(open('$TF'))['steps'],**{'$STEP':'done'})"
    set_field "$TF" "current_status" "'done'"
    set_field "$TF" "updated_at" "'$(date -Is)'"
    echo "✅ Step '$STEP' marked as done for task $TASK_ID"
    # If final step (done), merge branch back to master
    if [ "$STEP" = "done" ]; then
      "$SWARM_DIR/merge-task.sh" "$TASK_ID" 2>&1 || echo "⚠️ Merge skipped or failed"
    fi
    # Remind agent to log lessons
    AGENT=$(get_field "$TF" "agent")
    echo "📝 REMINDER: Run learn.sh lesson and learn.sh score before finishing!"
    echo "   swarm/learn.sh lesson $AGENT <severity> \"title\" \"description\""
    echo "   swarm/learn.sh score $AGENT success"
    ;;

  advance)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    STEP=$(get_field "$TF" "current_step")
    STATUS=$(get_field "$TF" "current_status")
    if [ "$STATUS" != "done" ]; then
      echo "❌ Cannot advance: step '$STEP' is '$STATUS' (must be 'done')"
      exit 1
    fi
    IDX=$(current_step_index "$TF")
    NEXT_IDX=$((IDX + 1))
    if [ $NEXT_IDX -ge ${#STEPS[@]} ]; then
      echo "✅ Task $TASK_ID is already at final step"
      exit 0
    fi
    NEXT="${STEPS[$NEXT_IDX]}"
    set_field "$TF" "current_step" "'$NEXT'"
    set_field "$TF" "current_status" "'active'"
    set_field "$TF" "steps" "dict(json.load(open('$TF'))['steps'],**{'$NEXT':'active'})"
    set_field "$TF" "updated_at" "'$(date -Is)'"
    echo "✅ Advanced to step '$NEXT' (active) for task $TASK_ID"
    ;;

  verify)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    URL="${3:-http://localhost:3000}"
    STEP=$(get_field "$TF" "current_step")
    echo "🔍 Running verify for task $TASK_ID (step: $STEP)..."
    case "$STEP" in
      verify_sandbox)
        "$VERIFY_DIR/verify-frontend.sh" "$URL"
        RESULT=$?
        ;;
      verify_prod)
        "$VERIFY_DIR/verify-frontend.sh" "$URL"
        RESULT=$?
        ;;
      *)
        echo "⚠️ Verify not applicable for step '$STEP'"
        exit 1
        ;;
    esac
    if [ $RESULT -eq 0 ]; then
      set_field "$TF" "current_status" "'done'"
      set_field "$TF" "steps" "dict(json.load(open('$TF'))['steps'],**{'$STEP':'done'})"
      set_field "$TF" "updated_at" "'$(date -Is)'"
      echo "✅ Verify passed — step '$STEP' marked done"
    else
      set_field "$TF" "current_status" "'failed'"
      set_field "$TF" "steps" "dict(json.load(open('$TF'))['steps'],**{'$STEP':'failed'})"
      echo "❌ Verify failed — step '$STEP' marked failed"
      exit 1
    fi
    ;;

  review)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    STEP=$(get_field "$TF" "current_step")
    if [ "$STEP" != "review" ]; then
      echo "❌ Cannot request review: current step is '$STEP' (must be 'review')"
      exit 1
    fi
    THREAD=$(get_field "$TF" "thread_id")
    AGENT=$(get_field "$TF" "agent_id")
    echo "📝 Review requested for task $TASK_ID (agent: $AGENT, thread: $THREAD)"
    echo "Posting review request to General..."
    "$SWARM_DIR/send.sh" or 1 "🔍 <b>בקשת Review</b>
📋 משימה: $TASK_ID
🤖 סוכן: $AGENT
🧵 Thread: $THREAD

לאישור: <code>pipeline.sh approve $TASK_ID</code>
לדחייה: <code>pipeline.sh reject $TASK_ID \"reason\"</code>"
    echo "✅ Review request posted"
    ;;

  approve)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    STEP=$(get_field "$TF" "current_step")
    if [ "$STEP" != "review" ]; then
      echo "❌ Cannot approve: current step is '$STEP' (must be 'review')"
      exit 1
    fi
    set_field "$TF" "current_status" "'done'"
    set_field "$TF" "steps" "dict(json.load(open('$TF'))['steps'],**{'review':'done'})"
    set_field "$TF" "updated_at" "'$(date -Is)'"
    echo "✅ Review approved for task $TASK_ID — ready to advance to deploy"
    ;;

  reject)
    [ -z "$TASK_ID" ] && usage
    TF=$(task_file "$TASK_ID")
    [ ! -f "$TF" ] && echo "❌ Task $TASK_ID not found" && exit 1
    REASON="${3:-no reason given}"
    # Reset back to sandbox
    set_field "$TF" "current_step" "'sandbox'"
    set_field "$TF" "current_status" "'active'"
    python3 -c "
import json
f='$TF'
d=json.load(open(f))
for s in d['steps']: d['steps'][s]='pending'
d['steps']['sandbox']='active'
json.dump(d,open(f,'w'),indent=2)
"
    set_field "$TF" "updated_at" "'$(date -Is)'"
    THREAD=$(get_field "$TF" "thread_id")
    AGENT=$(get_field "$TF" "agent_id")
    echo "❌ Review rejected for task $TASK_ID: $REASON"
    echo "Task reset to sandbox step"
    "$SWARM_DIR/send.sh" "$AGENT" "$THREAD" "❌ <b>Review נדחה:</b> $REASON
חזרת לשלב sandbox. תקן ודווח מחדש."
    ;;

  *)
    usage
    ;;
esac
