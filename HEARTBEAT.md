# HEARTBEAT.md

## 1. Agent Completion Verification (HIGHEST PRIORITY)
Check for completed agents that need verification:
```bash
# Check for done markers
for f in /tmp/agent-done/*.json; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f" .json)
  AGENT_ID=$(echo "$BASENAME" | rev | cut -d'-' -f2- | rev)
  THREAD_ID=$(echo "$BASENAME" | rev | cut -d'-' -f1 | rev)
  
  # Check if already verified
  META="/tmp/agent-tasks/${BASENAME}.json"
  if [ -f "$META" ]; then
    STATUS=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" < "$META" 2>/dev/null)
    [ "$STATUS" = "verified_pass" ] && continue
    [ "$STATUS" = "verified_fail" ] && continue
  fi
  
  echo "NEEDS VERIFY: $BASENAME"
done
```
- If any need verification → run `bash swarm/on-agent-done.sh <agent_id> <thread_id>`
- If PASS → report to Yossi in General
- If FAIL → agent gets retry instructions automatically
- If ESCALATE (3 fails) → report failure to Yossi honestly

## 2. Agent Chat Monitor (thread 479)
Check if any agent asked for help:
```bash
# Check recent agent-chat messages for help requests
tail -20 /root/.openclaw/workspace/swarm/logs/$(date +%Y-%m-%d).jsonl 2>/dev/null | grep -i "עזרה\|help\|stuck\|🆘"
```
- If agent asked for help → read what they need → provide it via send.sh to their topic
- Common requests: API tokens, credentials, config values, clarification on task

## 3. Retry Request Handler
```bash
for f in /tmp/retry-request-*.json; do
  [ -f "$f" ] || continue
  cat "$f"
  # Re-spawn the agent with issues as context, then delete file
  # rm "$f"
done
```

## 4. Stuck Agent Detection
```bash
# Check for agents running longer than 10 minutes without completion
for f in /tmp/agent-tasks/*.json; do
  [ -f "$f" ] || continue
  STATUS=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" < "$f" 2>/dev/null)
  [ "$STATUS" = "running" ] || continue
  
  DISPATCHED=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('dispatched_at',''))" < "$f" 2>/dev/null)
  echo "STILL RUNNING: $(basename $f) since $DISPATCHED"
done
```
- If running > 15 minutes → check subagents list for status
- If dead/timed out → report to Yossi

## 5. Nothing needed? → HEARTBEAT_OK
