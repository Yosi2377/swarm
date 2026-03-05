# HEARTBEAT.md

## 1. Smart-Eval Reports (HIGHEST PRIORITY)
Check for new evaluation reports and retry requests:
```bash
# Check for retry requests — re-spawn failed agents
for f in /tmp/retry-request-*.json; do
  [ -f "$f" ] || continue
  cat "$f"  # Read: label, topic, retry count, issues
  # Re-spawn the agent with extra context about what failed
  # Then delete: rm "$f"
done

# Check recent reports
bash /root/.openclaw/workspace/swarm/status.sh 10
```
- If retry-request exists → re-spawn the agent with issues as context
- If report says FAIL after max retries → escalate to Yossi

## 2. Agent Completion Monitor
- Run: `bash /root/.openclaw/workspace/swarm/monitor.sh` — scan logs for completions
- Check `/tmp/agent-done/` for completed agents
- For each: verify results, report to Yossi

## 3. Watchdog Alerts
- Check `/tmp/watchdog-alert.json`
- If exists: spawn koder to fix, delete file, report

## 4. Agent Activity Monitor
- `tail -5 /root/.openclaw/workspace/swarm/logs/$(date +%Y-%m-%d).jsonl 2>/dev/null`
- Track last checked timestamp in `/tmp/heartbeat-agent-last.txt`

## 5. Auto-Approve Handler
- Pattern `approve_XXXX` → `bash swarm/handle-approve.sh XXXX`
- Pattern `reject_XXXX` → `send.sh or 1 "❌ PR #XXXX rejected"`

## Nothing else needed? → HEARTBEAT_OK
