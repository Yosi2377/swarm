#!/bin/bash
# create-task.sh — Create a structured task using JSON schema
# Usage: create-task.sh <agent> <thread> <title> <description> [priority] [files] [deliverables] [success_criteria]
#
# Creates:
#   1. swarm/tasks/<thread>.json — structured task file
#   2. swarm/tasks/<thread>.md — human-readable task file
#   3. Registers in tasks.json via task.sh
#
# Example:
#   create-task.sh koder 4950 "Fix login" "Login button not working on mobile" high \
#     "public/js/app.js,public/index.html" "Working login on mobile" "Login works on 375px viewport"

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="${1:?Usage: create-task.sh <agent> <thread> <title> <description> [priority] [files] [deliverables] [success_criteria]}"
THREAD="${2:?Missing thread_id}"
TITLE="${3:?Missing title}"
DESCRIPTION="${4:?Missing description}"
PRIORITY="${5:-normal}"
FILES="${6:-}"
DELIVERABLES="${7:-}"
SUCCESS_CRITERIA="${8:-}"
CREATED_BY="${9:-or}"

NOW=$(date -Iseconds)
TASKS_DIR="$DIR/tasks"
mkdir -p "$TASKS_DIR"

# Convert comma-separated to JSON arrays
files_json() {
  if [ -z "$1" ]; then echo "[]"; return; fi
  echo "$1" | tr ',' '\n' | jq -R . | jq -s .
}

deliverables_json=$(files_json "$DELIVERABLES")
files_array=$(files_json "$FILES")
criteria_json=$(files_json "$SUCCESS_CRITERIA")

# Determine review agent
case "$AGENT" in
  koder)  REVIEW_AGENT="shomer" ;;
  shomer) REVIEW_AGENT="koder" ;;
  tzayar) REVIEW_AGENT="bodek" ;;
  *)      REVIEW_AGENT="koder" ;;
esac

# Create structured JSON task file
cat > "$TASKS_DIR/${THREAD}.json" <<EOF
{
  "schema": "task-schema-v2",
  "id": ${THREAD},
  "title": $(echo "$TITLE" | jq -R .),
  "agent": "${AGENT}",
  "thread": ${THREAD},
  "priority": "${PRIORITY}",
  "status": "active",
  "inputs": {
    "description": $(echo "$DESCRIPTION" | jq -R .),
    "files": ${files_array},
    "context": "",
    "dependencies": []
  },
  "expected_output": {
    "type": "code",
    "deliverables": ${deliverables_json},
    "success_criteria": ${criteria_json}
  },
  "constraints": {
    "sandbox_only": true,
    "max_retries": 3,
    "review_required": true,
    "review_agent": "${REVIEW_AGENT}"
  },
  "metadata": {
    "parent_task": null,
    "created_by": "${CREATED_BY}",
    "created_at": "${NOW}",
    "retry_count": 0,
    "retry_strategy": "same",
    "peer_review": null,
    "quality_score": null
  }
}
EOF

# Create human-readable task file
cat > "$TASKS_DIR/${THREAD}.md" <<EOF
# Task: ${TITLE}
- **Agent:** ${AGENT}
- **Thread:** ${THREAD}
- **Priority:** ${PRIORITY}
- **Created:** ${NOW}
- **Created by:** ${CREATED_BY}

## Description
${DESCRIPTION}

## Files
${FILES:-No specific files listed}

## Expected Output
${DELIVERABLES:-Not specified}

## Success Criteria
${SUCCESS_CRITERIA:-Not specified}

## Progress
<!-- Agent updates progress here -->

## Tests
<!-- Agent writes tests here -->

## Browser Tests
<!-- Agent writes browser tests here -->
EOF

# Register in tasks.json
bash "$DIR/task.sh" add "$AGENT" "$THREAD" "$TITLE" "$PRIORITY" 2>/dev/null

echo "✅ Structured task created:"
echo "   📄 JSON: $TASKS_DIR/${THREAD}.json"
echo "   📝 MD:   $TASKS_DIR/${THREAD}.md"
echo "   🎯 Agent: ${AGENT} | Priority: ${PRIORITY} | Review: ${REVIEW_AGENT}"
