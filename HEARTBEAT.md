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
    [ "$STATUS" = "passed" ] && continue
  fi
  
  echo "NEEDS VERIFY: $BASENAME"
done
```

**Verification flow (MANDATORY — do ALL steps):**
1. Run `bash swarm/verify-task.sh <agent_id> <thread_id>`
2. **REGARDLESS of verify result** — take your own screenshot:
   - Open the relevant URL in browser (clawd profile, 1280px viewport)
   - `browser action=screenshot`
   - Send screenshot to General (topic 1) via message tool with media
3. If PASS → report to Yossi: "✅ [task] הושלם — [summary]" + screenshot
4. If RETRY → re-spawn agent with enriched prompt from verify output
5. If ESCALATE → report failure honestly to Yossi with what went wrong
**⚠️ NEVER report done to Yossi without YOUR OWN screenshot. Agent screenshots are not enough.**

## 2. Watchdog — Detect Stuck Agents (NEW)
```bash
bash /root/.openclaw/workspace/swarm/watchdog.sh
```
- If any stuck agents detected, the output will show them
- Stuck agents are auto-flagged as `failed_retryable` with retry requests created
- Report stuck agents to Yossi if they've been stuck multiple times

## 3. Process Retry Requests (NEW)
```bash
bash /root/.openclaw/workspace/swarm/auto-retry-watcher.sh
```
- Processes both done markers AND retry requests from watchdog
- Auto-retries up to 3 times with enriched context
- Escalates after max retries
- Check output for any escalations that need human attention

## 4. Agent Chat Monitor (thread 479)
Check if any agent asked for help:
```bash
# Check recent agent-chat messages for help requests
tail -20 /root/.openclaw/workspace/swarm/logs/$(date +%Y-%m-%d).jsonl 2>/dev/null | grep -i "עזרה\|help\|stuck\|🆘"
```
- If agent asked for help → read what they need → provide it via send.sh to their topic
- Common requests: API tokens, credentials, config values, clarification on task

## 5. Nothing needed? → HEARTBEAT_OK
