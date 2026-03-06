#!/bin/bash
# save-lesson.sh — Save a lesson from agent success/failure
# Usage: bash save-lesson.sh <agent> <severity> <what> <lesson>
# Example: bash save-lesson.sh koder critical "getUsers returned all users" "Always filter by role in user queries"

AGENT="${1:?Usage: save-lesson.sh <agent> <severity> <what> <lesson>}"
SEVERITY="${2:-medium}"
WHAT="${3:-unknown}"
LESSON="${4:-no lesson recorded}"

DIR="$(cd "$(dirname "$0")" && pwd)"
LESSONS_FILE="$DIR/learning/lessons.json"

# Generate unique ID
ID=$(python3 -c "import uuid; print(uuid.uuid4().hex[:8])")

# Add lesson to JSON
python3 << PYEOF
import json, os
from datetime import datetime, timezone

lessons_file = "${LESSONS_FILE}"

# Load existing
data = {"version": 1, "lessons": []}
if os.path.exists(lessons_file):
    try:
        with open(lessons_file) as f:
            data = json.load(f)
    except:
        pass

# Ensure lessons is a list
if isinstance(data, list):
    data = {"version": 1, "lessons": data}

# Impact based on severity
impact_map = {"critical": 1.0, "high": 0.8, "medium": 0.7, "low": 0.3}
impact = impact_map.get("${SEVERITY}", 0.5)

new_lesson = {
    "id": "${ID}",
    "agent": "${AGENT}",
    "severity": "${SEVERITY}",
    "impact": impact,
    "what": """${WHAT}"""[:200],
    "lesson": """${LESSON}"""[:500],
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "applied": 0
}

data["lessons"].append(new_lesson)

with open(lessons_file, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"✅ Lesson saved: [{new_lesson['severity']}] {new_lesson['what'][:50]}")
PYEOF
