#!/bin/bash
# peer-review.sh — Auto-trigger peer review when a task is done
# Usage: peer-review.sh <task_id> <agent_id> <thread_id> [sandbox_url]
#
# Review routing:
#   koder's work → shomer reviews (security) + bodek reviews (QA)
#   shomer's work → koder reviews
#   tzayar's work → bodek reviews (visual QA)
#   researcher's work → koder reviews (accuracy)
#   worker's work → koder reviews
#
# Creates a review task file and queues delegation

DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_ID="$1"
AGENT="$2"
THREAD="$3"
SANDBOX_URL="${4:-}"

if [ -z "$TASK_ID" ] || [ -z "$AGENT" ] || [ -z "$THREAD" ]; then
  echo "Usage: peer-review.sh <task_id> <agent_id> <thread_id> [sandbox_url]"
  exit 1
fi

# Determine reviewer based on agent
case "$AGENT" in
  koder)    REVIEWER="shomer"; REVIEWER_NAME="שומר"; REVIEWER_EMOJI="🔒"; REVIEW_TYPE="security+code" ;;
  shomer)   REVIEWER="koder";  REVIEWER_NAME="קודר"; REVIEWER_EMOJI="⚙️"; REVIEW_TYPE="code" ;;
  tzayar)   REVIEWER="bodek";  REVIEWER_NAME="בודק"; REVIEWER_EMOJI="🧪"; REVIEW_TYPE="visual-qa" ;;
  researcher) REVIEWER="koder"; REVIEWER_NAME="קודר"; REVIEWER_EMOJI="⚙️"; REVIEW_TYPE="accuracy" ;;
  worker)   REVIEWER="koder";  REVIEWER_NAME="קודר"; REVIEWER_EMOJI="⚙️"; REVIEW_TYPE="general" ;;
  bodek)    REVIEWER="shomer"; REVIEWER_NAME="שומר"; REVIEWER_EMOJI="🔒"; REVIEW_TYPE="security" ;;
  *)        REVIEWER="koder";  REVIEWER_NAME="קודר"; REVIEWER_EMOJI="⚙️"; REVIEW_TYPE="general" ;;
esac

NOW=$(date -Iseconds)
REVIEW_DIR="$DIR/reviews"
mkdir -p "$REVIEW_DIR"

# Read task file for context
TASK_FILE="$DIR/tasks/${THREAD}.md"
TASK_CONTEXT=""
if [ -f "$TASK_FILE" ]; then
  TASK_CONTEXT=$(head -50 "$TASK_FILE")
fi

# Check for task JSON (structured schema)
TASK_JSON="$DIR/tasks/${THREAD}.json"
TASK_JSON_CONTEXT=""
if [ -f "$TASK_JSON" ]; then
  TASK_JSON_CONTEXT=$(cat "$TASK_JSON")
fi

# Create review file
REVIEW_FILE="$REVIEW_DIR/review-${TASK_ID}-${REVIEWER}.md"
cat > "$REVIEW_FILE" <<EOF
# Peer Review — Task #${TASK_ID}
- **Original Agent:** ${AGENT}
- **Reviewer:** ${REVIEWER} (${REVIEWER_EMOJI} ${REVIEWER_NAME})
- **Review Type:** ${REVIEW_TYPE}
- **Thread:** ${THREAD}
- **Sandbox URL:** ${SANDBOX_URL:-N/A}
- **Created:** ${NOW}
- **Status:** pending

## Review Checklist

### Security (if applicable)
- [ ] No hardcoded secrets/passwords
- [ ] No SQL injection / XSS vulnerabilities
- [ ] Input validation present
- [ ] No production paths modified

### Code Quality
- [ ] Code is readable and documented
- [ ] No obvious bugs or logic errors
- [ ] Error handling present
- [ ] DRY — no unnecessary duplication

### Functionality
- [ ] Meets task requirements (check task description)
- [ ] Edge cases handled
- [ ] No regression on existing features

### Visual (if UI change)
- [ ] Responsive (mobile/tablet/desktop)
- [ ] Consistent with design system
- [ ] No visual glitches

## Task Context
\`\`\`
${TASK_CONTEXT:-No task file found}
\`\`\`

## Task Schema
\`\`\`json
${TASK_JSON_CONTEXT:-No structured task JSON found}
\`\`\`

## Review Result
<!-- Reviewer fills this in -->
- **Verdict:** PENDING
- **Score:** /10
- **Notes:**
EOF

# Queue delegation for review
DELEGATE_DIR="/tmp/delegate-queue"
mkdir -p "$DELEGATE_DIR"

cat > "$DELEGATE_DIR/review-${TASK_ID}-$(date +%s).json" <<EOF
{
  "from": "${AGENT}",
  "to": "${REVIEWER}",
  "thread": ${THREAD},
  "type": "peer-review",
  "task_id": ${TASK_ID},
  "review_file": "${REVIEW_FILE}",
  "sandbox_url": "${SANDBOX_URL}",
  "message": "${REVIEWER_EMOJI} בקשת Review — Task #${TASK_ID}\nסוכן: ${AGENT} סיים עבודה בthread ${THREAD}.\nסוג review: ${REVIEW_TYPE}\nקובץ: ${REVIEW_FILE}\n${SANDBOX_URL:+URL: ${SANDBOX_URL}}\nבדוק את העבודה ומלא את ה-checklist.",
  "created": "${NOW}"
}
EOF

# Notify in Agent Chat (479)
bash "$DIR/send.sh" "$AGENT" 479 "[${AGENT^^}] → [${REVIEWER_EMOJI}] | TYPE: review-request
📋 Task #${TASK_ID} (thread ${THREAD}) מוכן ל-review.
סוג: ${REVIEW_TYPE}
${SANDBOX_URL:+🔗 ${SANDBOX_URL}}" 2>/dev/null

echo "✅ Peer review queued: ${REVIEWER_EMOJI} ${REVIEWER_NAME} will review task #${TASK_ID} (${REVIEW_TYPE})"
echo "📄 Review file: ${REVIEW_FILE}"
echo "📬 Delegation queued in /tmp/delegate-queue/"
