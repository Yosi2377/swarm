#!/bin/bash
# router.sh — Smart Intent Router: auto-classify tasks to the right agent
# Usage: router.sh "<task description>"
# Returns: recommended agent + confidence

TASK="${1:-}"
if [ -z "$TASK" ]; then
  echo "Usage: router.sh \"<task description>\""
  exit 1
fi

TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

# Scoring arrays
SHOMER=0; KODER=0; TZAYAR=0; RESEARCHER=0; WORKER=0

# ─── Security keywords → שומר ───
for kw in אבטחה סריקה פורט ssl https firewall חדיר vulnerability security scan port hack breach password secret csrf xss injection pentest audit hardening; do
  echo "$TASK_LOWER" | grep -qi "$kw" && SHOMER=$((SHOMER + 10))
done

# ─── Code keywords → קודר ───
for kw in קוד באג bug fix deploy api endpoint server backend frontend html css js node mongodb database route function script service restart port error crash build compile npm git commit push pull "שנה קוד" "תתקן" "תוסיף" "תבנה" refactor migrate test jest; do
  echo "$TASK_LOWER" | grep -qi "$kw" && KODER=$((KODER + 10))
done

# ─── Design keywords → צייר ───
for kw in עיצוב תמונה לוגו logo ui ux design image icon avatar color font theme css animation responsive layout mockup figma pixel; do
  echo "$TASK_LOWER" | grep -qi "$kw" && TZAYAR=$((TZAYAR + 10))
done

# ─── Research keywords → חוקר ───
for kw in מחקר חפש research compare "best practice" benchmark analysis survey alternatives api documentation "how to" framework library tool review; do
  echo "$TASK_LOWER" | grep -qi "$kw" && RESEARCHER=$((RESEARCHER + 10))
done

# ─── General/worker ───
for kw in נקה organize cleanup sort move copy backup file folder; do
  echo "$TASK_LOWER" | grep -qi "$kw" && WORKER=$((WORKER + 10))
done

# Find max score
MAX=0; AGENT="worker"; CONFIDENCE="low"
for pair in "shomer:$SHOMER" "koder:$KODER" "tzayar:$TZAYAR" "researcher:$RESEARCHER" "worker:$WORKER"; do
  NAME="${pair%%:*}"
  SCORE="${pair##*:}"
  if [ "$SCORE" -gt "$MAX" ]; then
    MAX=$SCORE
    AGENT=$NAME
  fi
done

# Confidence based on score gap
SECOND=0
for pair in "shomer:$SHOMER" "koder:$KODER" "tzayar:$TZAYAR" "researcher:$RESEARCHER" "worker:$WORKER"; do
  NAME="${pair%%:*}"
  SCORE="${pair##*:}"
  if [ "$SCORE" -gt "$SECOND" ] && [ "$NAME" != "$AGENT" ]; then
    SECOND=$SCORE
  fi
done

GAP=$((MAX - SECOND))
if [ "$MAX" -eq 0 ]; then
  CONFIDENCE="none"
  AGENT="worker"
elif [ "$GAP" -ge 20 ]; then
  CONFIDENCE="high"
elif [ "$GAP" -ge 10 ]; then
  CONFIDENCE="medium"
else
  CONFIDENCE="low"
fi

# Agent emoji
declare -A EMOJI=([shomer]="🔒" [koder]="⚙️" [tzayar]="🎨" [researcher]="🔍" [worker]="🤖")
declare -A NAMES=([shomer]="שומר" [koder]="קודר" [tzayar]="צייר" [researcher]="חוקר" [worker]="עובד")

echo "AGENT=$AGENT"
echo "NAME=${NAMES[$AGENT]}"
echo "EMOJI=${EMOJI[$AGENT]}"
echo "CONFIDENCE=$CONFIDENCE"
echo "SCORES: 🔒$SHOMER ⚙️$KODER 🎨$TZAYAR 🔍$RESEARCHER 🤖$WORKER"
