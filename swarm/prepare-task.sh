#!/bin/bash
# Usage: prepare-task.sh "keywords" 
# Outputs relevant lessons to include in task prompt
# Orchestrator runs this BEFORE sending tasks to agents

KEYWORDS="$1"
if [ -z "$KEYWORDS" ]; then
  echo "Usage: prepare-task.sh \"keywords\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "📚 לקחים רלוונטיים מהמערכת:"
echo "================================"
"$SCRIPT_DIR/learn.sh" query "$KEYWORDS" 2>/dev/null | head -20
echo "================================"
echo ""
echo "⚠️ סוכן: קרא את הלקחים למעלה לפני שמתחיל! הם מבוססים על טעויות קודמות."
