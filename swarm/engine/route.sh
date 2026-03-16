#!/bin/bash
# route.sh — Smart agent routing based on task description
# Inspired by Ruflo's router.js
# Usage: route.sh "task description"
# Output: agent_id (e.g., koder, shomer, tzayar, etc.)

set -uo pipefail

TASK_DESC="${1:?Usage: route.sh \"task description\"}"
SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TASK_LOWER=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]')

# Agent routing patterns (ordered by specificity)
declare -A PATTERNS
PATTERNS[shomer]='security|vulnerability|ssl|tls|certificate|firewall|port scan|penetration|hardening|אבטחה|סריקה|פורטים'
PATTERNS[tzayar]='design|logo|image|icon|ui design|mockup|wireframe|illustration|עיצוב|תמונה|לוגו|איור'
PATTERNS[front]='html|css|javascript|responsive|frontend|front-end|react|vue|angular|component|layout|button|style|כפתור|צבע|עיצוב'
PATTERNS[back]='backend|back-end|api|endpoint|server|express|node\.js|rest|graphql|authentication|middleware'
PATTERNS[data]='database|mongodb|sql|migration|backup|schema|collection|query|index|דאטא|מסד נתונים'
PATTERNS[docker]='docker|container|kubernetes|k8s|devops|ci.cd|pipeline|deploy|infrastructure|nginx'
PATTERNS[tester]='test|e2e|unit test|integration test|coverage|qa|בדיקה|טסט'
PATTERNS[debugger]='debug|error tracking|log analysis|profiling|stack trace|דיבאג|שגיאה'
PATTERNS[refactor]='refactor|optimize code|tech debt|clean.?up|restructure|ריפקטור'
PATTERNS[monitor]='monitor|alert|health.?check|uptime|grafana|prometheus|מוניטור'
PATTERNS[optimizer]='performance|speed|caching|optimization|lazy load|bundle size|אופטימיזציה'
PATTERNS[integrator]='webhook|third.party|integration|external api|stripe|twilio|אינטגרציה'
PATTERNS[researcher]='research|best practice|investigate|compare|documentation|explore|מחקר|חקור'
PATTERNS[koder]='fix|bug|broken|crash|error|repair|code|implement|create|build|feature|add|write|תקן|באג|קוד|פיצ׳ר'
PATTERNS[worker]='.'  # fallback

# Score each agent
BEST_AGENT="worker"
BEST_SCORE=0

for agent in shomer tzayar front back data docker tester debugger refactor monitor optimizer integrator researcher koder; do
  pattern="${PATTERNS[$agent]}"
  # Count keyword matches
  score=0
  for keyword in $(echo "$pattern" | tr '|' ' '); do
    if echo "$TASK_LOWER" | grep -qE "$keyword" 2>/dev/null; then
      score=$((score + 1))
    fi
  done

  # Boost by past success rate from learning system
  if [ $score -gt 0 ] && [ -f "${SWARM_DIR}/learning/scores.json" ]; then
    agent_score=$(jq -r ".\"${agent}\".success // 0" "${SWARM_DIR}/learning/scores.json" 2>/dev/null)
    if [ "$agent_score" != "null" ] && [ "$agent_score" -gt 5 ] 2>/dev/null; then
      score=$((score + 1))
    fi
  fi

  if [ $score -gt $BEST_SCORE ]; then
    BEST_SCORE=$score
    BEST_AGENT=$agent
  fi
done

echo "$BEST_AGENT"
