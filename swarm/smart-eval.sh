#!/bin/bash
# smart-eval.sh v4 — Full autonomous pipeline
# Poll → Detect done → Strict eval → Auto-retry via hooks → Pipeline chain
#
# Usage: nohup bash smart-eval.sh <label> <topic> <eval> [max_wait] [original_task] [next_step_json] &
#
# next_step_json format (optional, for pipeline chaining):
#   {"task":"...","eval":"...","label":"step2-shomer","timeout":120}

LABEL="${1:?Usage: smart-eval.sh <label> <topic> <eval> [max_wait] [original_task] [next_step_json]}"
TOPIC="${2:-4950}"
EVAL="${3:-Run tests and check the work}"
MAX_WAIT="${4:-300}"
ORIGINAL_TASK="${5:-}"
NEXT_STEP="${6:-}"

HOOK_TOKEN=$(python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json')).get('hooks',{}).get('token',''))" 2>/dev/null)
OR_TOKEN=$(cat /root/.openclaw/workspace/swarm/.bot-token 2>/dev/null)
CHAT_ID="-1003815143703"
SESSIONS_FILE="/root/.openclaw/agents/main/sessions/sessions.json"
REPORT_DIR="/tmp/agent-reports"
RETRY_FILE="/tmp/retry-${LABEL}.count"
LOG="/tmp/smart-eval-${LABEL}.log"

mkdir -p "$REPORT_DIR"
echo "$(date -Iseconds) START: ${LABEL} (max ${MAX_WAIT}s)" > "$LOG"

# ─── PHASE 1: POLL until agent finishes ───
sleep 10
ELAPSED=10
LAST_UPDATE=0
STABLE_COUNT=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  
  CURRENT_UPDATE=$(python3 -c "
import json
with open('${SESSIONS_FILE}') as f:
    data = json.load(f)
best = 0
for key, val in data.items():
    if 'subagent' in key:
        t = val.get('updatedAt', 0)
        if t > best: best = t
print(best)
" 2>/dev/null)
  
  if [ "$CURRENT_UPDATE" = "$LAST_UPDATE" ] && [ "$LAST_UPDATE" != "0" ]; then
    STABLE_COUNT=$((STABLE_COUNT + 1))
  else
    STABLE_COUNT=0
    LAST_UPDATE="$CURRENT_UPDATE"
  fi
  
  if [ $STABLE_COUNT -ge 3 ]; then
    echo "$(date -Iseconds) DONE: stable 45s (${ELAPSED}s)" >> "$LOG"
    break
  fi
done

STATUS="done"
[ $ELAPSED -ge $MAX_WAIT ] && STATUS="timeout"
echo "$(date -Iseconds) STATUS: ${STATUS} (${ELAPSED}s)" >> "$LOG"

# ─── PHASE 2: STRICT EVALUATION via hook agent ───
curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
  -d "text=🔍 סוכן ${LABEL} ${STATUS} (${ELAPSED}s). מעריך..." > /dev/null 2>&1

EVAL_TMPFILE="/tmp/eval-payload-${LABEL}.json"
python3 << 'PYEOF' - "${LABEL}" "${STATUS}" "${ELAPSED}" "${EVAL}" "${REPORT_DIR}" "${CHAT_ID}" "${TOPIC}"
import json, sys

label, status, elapsed, eval_instructions, report_dir, chat_id, topic = sys.argv[1:8]

eval_prompt = open('/root/.openclaw/workspace/swarm/eval-prompt.md').read()

payload = {
    "task": f"""STRICT CODE REVIEW for agent {label} ({status}, {elapsed}s).

{eval_prompt}

SPECIFIC CHECKS FOR THIS TASK:
{eval_instructions}

MANDATORY STEPS:
1. Run the tests/checks yourself — do NOT trust any prior output
2. Read the actual code that was changed
3. Look for: hardcoded values, faked data, modified test files, empty catch blocks
4. If tests pass but implementation is fake/wrong → verdict SUSPECT
5. Write verdict to {report_dir}/{label}.json:
   {{"label":"{label}","status":"pass or fail or suspect","summary":"...","tests":{{"passed":0,"failed":0,"total":0}},"issues":["..."],"verdict_reason":"why"}}
6. Send Hebrew report to Telegram: use message tool with action=send, channel=telegram, target={chat_id}, threadId={topic}
   Format: PASS ✅ / FAIL ❌ / SUSPECT ⚠️ + details""",
    "sessionKey": f"hook:eval:{label}-{elapsed}"
}

with open(f"/tmp/eval-payload-{label}.json", "w") as f:
    json.dump(payload, f, ensure_ascii=False)
PYEOF

curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
  -H "Authorization: Bearer ${HOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @"${EVAL_TMPFILE}" >> "$LOG" 2>&1
rm -f "${EVAL_TMPFILE}"

echo "" >> "$LOG"
echo "$(date -Iseconds) EVAL triggered" >> "$LOG"

# ─── PHASE 3: WAIT for eval → CHECK → RETRY or CHAIN ───
sleep 60  # Give eval agent time

RETRIES=0
[ -f "$RETRY_FILE" ] && RETRIES=$(cat "$RETRY_FILE")

REPORT_STATUS="unknown"
VERDICT_REASON=""
ISSUES_TEXT=""
if [ -f "${REPORT_DIR}/${LABEL}.json" ]; then
  read REPORT_STATUS VERDICT_REASON ISSUES_TEXT <<< $(python3 -c "
import json
with open('${REPORT_DIR}/${LABEL}.json') as f:
    d = json.load(f)
status = d.get('status', 'unknown').lower()
reason = d.get('verdict_reason', '')[:200].replace(' ', '_')
issues = '; '.join(d.get('issues', []))[:200].replace(' ', '_')
print(status, reason, issues)
" 2>/dev/null)
fi

echo "$(date -Iseconds) RESULT: ${REPORT_STATUS} (retries: ${RETRIES})" >> "$LOG"

case "$REPORT_STATUS" in
  pass|fixed*|complete*|success*)
    # ─── SUCCESS ───
    echo "$(date -Iseconds) ✅ PASS" >> "$LOG"
    rm -f "$RETRY_FILE"
    
    # ─── PIPELINE: trigger next step if defined ───
    if [ -n "$NEXT_STEP" ] && [ "$NEXT_STEP" != "" ] && [ "$NEXT_STEP" != "{}" ]; then
      # Verify next step has actual task content
      HAS_TASK=$(echo "$NEXT_STEP" | python3 -c "import json,sys;d=json.load(sys.stdin);print('yes' if d.get('task') else 'no')" 2>/dev/null)
      if [ "$HAS_TASK" != "yes" ]; then
        echo "$(date -Iseconds) 🔗 PIPELINE: no valid next step, skipping" >> "$LOG"
      else
      echo "$(date -Iseconds) 🔗 PIPELINE: triggering next step" >> "$LOG"
      
      NEXT_TASK=$(echo "$NEXT_STEP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('task',''))" 2>/dev/null)
      NEXT_EVAL=$(echo "$NEXT_STEP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('eval',''))" 2>/dev/null)
      NEXT_LABEL=$(echo "$NEXT_STEP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('label','step-next'))" 2>/dev/null)
      NEXT_TIMEOUT=$(echo "$NEXT_STEP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('timeout',180))" 2>/dev/null)
      NEXT_NEXT=$(echo "$NEXT_STEP" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin).get('next',{})))" 2>/dev/null)
      
      curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
        -d "text=🔗 Pipeline: ${LABEL} עבר ✅ → מפעיל ${NEXT_LABEL}..." > /dev/null 2>&1
      
      # Spawn next step via hooks (it will run as an agent)
      NEXT_TMPFILE="/tmp/next-step-${NEXT_LABEL}.json"
      python3 -c "
import json
payload = {
    'task': '''${NEXT_TASK}''',
    'sessionKey': 'hook:pipeline:${NEXT_LABEL}'
}
with open('${NEXT_TMPFILE}', 'w') as f:
    json.dump(payload, f)
"
      curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
        -H "Authorization: Bearer ${HOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @"${NEXT_TMPFILE}" >> "$LOG" 2>&1
      rm -f "${NEXT_TMPFILE}"
      
      # Start monitoring next step
      nohup bash /root/.openclaw/workspace/swarm/smart-eval.sh \
        "${NEXT_LABEL}" "${TOPIC}" "${NEXT_EVAL}" "${NEXT_TIMEOUT}" "${NEXT_TASK}" \
        "${NEXT_NEXT}" > /dev/null 2>&1 &
      
      echo "$(date -Iseconds) 🔗 Next step ${NEXT_LABEL} spawned (monitor PID $!)" >> "$LOG"
      fi
    fi
    ;;
    
  fail|suspect)
    if [ "$RETRIES" -lt 2 ] && [ -n "$ORIGINAL_TASK" ]; then
      # ─── AUTO-RETRY: spawn new agent via hooks ───
      echo $((RETRIES + 1)) > "$RETRY_FILE"
      RETRY_NUM=$((RETRIES + 1))
      
      ISSUES_READABLE=$(python3 -c "
import json
try:
    with open('${REPORT_DIR}/${LABEL}.json') as f:
        d = json.load(f)
    print('; '.join(d.get('issues', ['Unknown']))[:300])
except: print('Unknown issues')
" 2>/dev/null)
      
      curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
        -d "text=🔄 ניסיון ${RETRY_NUM}/2 — ${LABEL} נכשל. מפעיל שוב..." > /dev/null 2>&1
      
      # Spawn retry agent via hooks
      RETRY_LABEL="${LABEL}-retry${RETRY_NUM}"
      RETRY_TMPFILE="/tmp/retry-payload-${RETRY_LABEL}.json"
      python3 << RETRYEOF
import json
issues = """${ISSUES_READABLE}"""
original = """${ORIGINAL_TASK}"""
payload = {
    "task": f"""RETRY #{int('${RETRY_NUM}')} — Previous attempt FAILED.

ORIGINAL TASK:
{original}

PREVIOUS ISSUES (you MUST fix these):
{issues}

Do NOT repeat the same mistakes. Fix the issues listed above.
Write report to ${REPORT_DIR}/${RETRY_LABEL}.json""",
    "sessionKey": "hook:retry:${RETRY_LABEL}"
}
with open("${RETRY_TMPFILE}", "w") as f:
    json.dump(payload, f, ensure_ascii=False)
RETRYEOF
      
      curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
        -H "Authorization: Bearer ${HOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @"${RETRY_TMPFILE}" >> "$LOG" 2>&1
      rm -f "${RETRY_TMPFILE}"
      
      # Monitor the retry
      nohup bash /root/.openclaw/workspace/swarm/smart-eval.sh \
        "${RETRY_LABEL}" "${TOPIC}" "${EVAL}" "${MAX_WAIT}" "${ORIGINAL_TASK}" \
        "${NEXT_STEP}" > /dev/null 2>&1 &
      
      echo "$(date -Iseconds) 🔄 RETRY ${RETRY_NUM} spawned: ${RETRY_LABEL} (monitor PID $!)" >> "$LOG"
    else
      # ─── CROSS-AGENT HELP: Ask in Agent Chat (topic 479) ───
      HELP_FILE="/tmp/help-requested-${LABEL}"
      
      if [ ! -f "$HELP_FILE" ]; then
        # First time hitting max retries → ask other agents for help
        touch "$HELP_FILE"
        
        ISSUES_READABLE=$(python3 -c "
import json
try:
    with open('${REPORT_DIR}/${LABEL}.json') as f:
        d = json.load(f)
    print('; '.join(d.get('issues', ['Unknown']))[:300])
except: print('Unknown issues')
" 2>/dev/null)
        
        # Detect which agent type to ask for help
        HELPER="worker"
        echo "$LABEL" | grep -qi "koder\|code\|fix\|bug" && HELPER="debugger"
        echo "$LABEL" | grep -qi "shomer\|security\|auth" && HELPER="koder"
        echo "$LABEL" | grep -qi "front\|css\|ui" && HELPER="koder"
        echo "$LABEL" | grep -qi "data\|mongo\|db" && HELPER="koder"
        
        # Post help request in Agent Chat (topic 479)
        SWARM_DIR="/root/.openclaw/workspace/swarm"
        bash "${SWARM_DIR}/send.sh" "${HELPER}" 479 \
          "🆘 צריך עזרה! סוכן ${LABEL} נכשל אחרי 2 ניסיונות בנושא ${TOPIC}. בעיות: ${ISSUES_READABLE}" 2>/dev/null
        
        # Notify in the task topic
        curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
          -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
          -d "text=🤝 ${LABEL} נכשל 2 פעמים. ביקשתי עזרה מ-${HELPER} ב-Agent Chat. ממתין..." > /dev/null 2>&1
        
        # Spawn helper agent with full context
        HELPER_LABEL="${LABEL}-help-${HELPER}"
        HELPER_TMPFILE="/tmp/helper-payload-${HELPER_LABEL}.json"
        python3 << HELPEOF
import json
issues = """${ISSUES_READABLE}"""
original = """${ORIGINAL_TASK}"""
payload = {
    "task": f"""HELP REQUEST — Another agent failed this task twice. You are a different specialist being called in.

ORIGINAL TASK:
{original}

WHAT WENT WRONG (2 failed attempts):
{issues}

The previous agent could NOT solve this. Try a DIFFERENT approach:
- Read the code fresh, don't assume the previous agent's approach was correct
- Consider if the task itself needs reframing
- If you also cannot solve it, write status "escalate" in your report

Write report to /tmp/agent-reports/{HELPER_LABEL}.json""",
    "sessionKey": f"hook:help:{HELPER_LABEL}"
}
with open("/tmp/helper-payload-{HELPER_LABEL}.json", "w") as f:
    json.dump(payload, f, ensure_ascii=False)
HELPEOF
        
        curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
          -H "Authorization: Bearer ${HOOK_TOKEN}" \
          -H "Content-Type: application/json" \
          -d @"${HELPER_TMPFILE}" >> "$LOG" 2>&1
        rm -f "${HELPER_TMPFILE}"
        
        # Monitor helper — if helper also fails, THEN escalate to Yossi
        # Reset retry count for helper's evaluation
        rm -f "/tmp/retry-${HELPER_LABEL}.count"
        echo "0" > "/tmp/retry-${HELPER_LABEL}.count"
        
        nohup bash /root/.openclaw/workspace/swarm/smart-eval.sh \
          "${HELPER_LABEL}" "${TOPIC}" "${EVAL}" "${MAX_WAIT}" "${ORIGINAL_TASK}" \
          "${NEXT_STEP}" > /dev/null 2>&1 &
        
        echo "$(date -Iseconds) 🤝 CROSS-AGENT HELP: ${HELPER} called in (PID $!)" >> "$LOG"
      else
        # Helper also failed → Layer 4: Or (orchestrator) intervenes personally
        OR_INTERVENE_FILE="/tmp/or-intervened-${LABEL}"
        
        if [ ! -f "$OR_INTERVENE_FILE" ]; then
          # Or hasn't tried yet → wake Or to handle it personally
          touch "$OR_INTERVENE_FILE"
          
          # Collect all failure context
          ALL_ISSUES=$(python3 -c "
import json, glob, os
issues = []
for f in sorted(glob.glob('/tmp/agent-reports/${LABEL}*.json')):
    try:
        d = json.load(open(f))
        label = os.path.basename(f).replace('.json','')
        status = d.get('status','?')
        iss = d.get('issues', [])
        issues.append(f'{label}: {status} — {\";\".join(iss)[:100]}')
    except: pass
print('\n'.join(issues)[:500])
" 2>/dev/null)
          
          curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
            -d "text=🧠 סוכנים נכשלו 3 פעמים. אני (אור) מתערב אישית..." > /dev/null 2>&1
          
          # Wake Or's main session via hooks to handle this
          OR_TMPFILE="/tmp/or-intervene-${LABEL}.json"
          python3 << OREOF
import json
all_issues = """${ALL_ISSUES}"""
original = """${ORIGINAL_TASK}"""
eval_cmd = """${EVAL}"""
payload = {
    "task": f"""ORCHESTRATOR INTERVENTION — I need to handle this myself. Agents failed 3 times.

TASK: {original}

ALL PREVIOUS FAILURES:
{all_issues}

EVAL COMMAND: {eval_cmd}

MY JOB:
1. Read the actual code and understand the problem
2. Analyze WHY agents kept failing
3. Fix it myself using exec/edit tools
4. Run the eval command to verify
5. If I succeed → send PASS report to topic ${TOPIC}
6. If I truly cannot fix it → escalate to Yossi with honest explanation of what's wrong and why

Write report to /tmp/agent-reports/${LABEL}-or-fix.json
Send result to Telegram: message tool action=send, channel=telegram, target=${CHAT_ID}, threadId=${TOPIC}""",
    "sessionKey": "hook:or-intervene:${LABEL}"
}
with open("/tmp/or-intervene-${LABEL}.json", "w") as f:
    json.dump(payload, f, ensure_ascii=False)
OREOF
          
          curl -s -X POST "http://localhost:18789/hooks/agent-watcher" \
            -H "Authorization: Bearer ${HOOK_TOKEN}" \
            -H "Content-Type: application/json" \
            -d @"${OR_TMPFILE}" >> "$LOG" 2>&1
          rm -f "${OR_TMPFILE}"
          
          # Monitor Or's attempt — if Or also fails, THEN escalate to Yossi
          OR_FIX_LABEL="${LABEL}-or-fix"
          rm -f "/tmp/retry-${OR_FIX_LABEL}.count"
          rm -f "/tmp/help-requested-${OR_FIX_LABEL}"
          rm -f "/tmp/or-intervened-${OR_FIX_LABEL}"
          
          nohup bash /root/.openclaw/workspace/swarm/smart-eval.sh \
            "${OR_FIX_LABEL}" "${TOPIC}" "${EVAL}" "${MAX_WAIT}" "${ORIGINAL_TASK}" \
            "${NEXT_STEP}" > /dev/null 2>&1 &
          
          echo "$(date -Iseconds) 🧠 OR INTERVENING personally (PID $!)" >> "$LOG"
        else
          # Or also failed → Layer 5: FINAL escalation to Yossi
          curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" -d "message_thread_id=${TOPIC}" \
            -d "text=🚨 משימה ${LABEL} — נכשלה בכל 5 השכבות: סוכן (×2), סוכן עזרה, אור. דורש התערבות שלך יוסי!" > /dev/null 2>&1
          
          # Post in General for visibility
          curl -s "https://api.telegram.org/bot${OR_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" -d "message_thread_id=1" \
            -d "text=🚨 משימה ${LABEL} (נושא ${TOPIC}) — 5 שכבות נכשלו. באמת צריך אותך!" > /dev/null 2>&1
          
          echo "$(date -Iseconds) 🚨 FINAL ESCALATION to Yossi — all 5 layers failed" >> "$LOG"
          rm -f "$RETRY_FILE" "$HELP_FILE" "$OR_INTERVENE_FILE"
        fi
      fi
    fi
    ;;
    
  *)
    # Unknown status — eval agent might not have written report
    echo "$(date -Iseconds) ⚠️ Unknown status: ${REPORT_STATUS}" >> "$LOG"
    # Check if tests pass anyway
    if [ -n "$EVAL" ]; then
      echo "$(date -Iseconds) Running eval directly..." >> "$LOG"
      DIRECT_RESULT=$(bash -c "${EVAL}" 2>&1 | tail -5)
      echo "$(date -Iseconds) Direct eval: ${DIRECT_RESULT}" >> "$LOG"
    fi
    rm -f "$RETRY_FILE"
    ;;
esac

echo "$(date -Iseconds) END" >> "$LOG"
