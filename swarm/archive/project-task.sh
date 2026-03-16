#!/bin/bash
# project-task.sh — Route task to correct project
# Usage: project-task.sh PROJECT_KEY TASK_ID AGENT "DESCRIPTION"
PROJECT="$1"
TASK_ID="$2"
AGENT="$3"
DESC="$4"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CONFIG="$SCRIPT_DIR/projects.json"
if [ ! -f "$CONFIG" ]; then
  echo "❌ projects.json not found"
  exit 1
fi

# Read project config
PATH_VAL=$(python3 -c "import json;d=json.load(open('$CONFIG'));p=d['projects']['$PROJECT'];print(p.get('sandbox',p['path']))" 2>/dev/null)
URL_VAL=$(python3 -c "import json;d=json.load(open('$CONFIG'));p=d['projects']['$PROJECT'];print(p.get('sandboxUrl',p['url']))" 2>/dev/null)
PUBLIC=$(python3 -c "import json;d=json.load(open('$CONFIG'));print(d['projects']['$PROJECT']['publicDir'])" 2>/dev/null)
SERVICES=$(python3 -c "import json;d=json.load(open('$CONFIG'));p=d['projects']['$PROJECT'];print(' '.join(p.get('sandboxServices',p['services'])))" 2>/dev/null)

if [ -z "$PATH_VAL" ]; then
  echo "❌ Unknown project: $PROJECT (use: betting, poker, blackjack)"
  exit 1
fi

echo "🎯 Project: $PROJECT"
echo "📂 Path: $PATH_VAL"
echo "🌐 URL: $URL_VAL"
echo "📁 Public: $PUBLIC"
echo "⚙️ Services: $SERVICES"
echo ""
echo "Agent instructions:"
echo "  1. Edit files in: $PATH_VAL/$PUBLIC/"
echo "  2. Restart: systemctl restart $SERVICES"
echo "  3. Run pipeline: bash $SCRIPT_DIR/pipeline.sh $TASK_ID $AGENT $PATH_VAL/$PUBLIC/index.html \"$DESC\""
