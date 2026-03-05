# HEARTBEAT.md

## Agent Completion Monitor (ABSOLUTE FIRST PRIORITY)
- Run: `bash /root/.openclaw/workspace/swarm/monitor.sh` — scan logs for new completions
- Run: `bash /root/.openclaw/workspace/swarm/auto-report.sh` — report unreported completions
- Check `/tmp/agent-done/` for any completed agents:
  - For each completed: verify results, report to Yossi
  - If results look good → confirm in the agent's topic
  - If results look bad → re-spawn or escalate

## Watchdog Alerts (SECOND PRIORITY)
- Check if `/tmp/watchdog-alert.json` exists
- If YES:
  1. Read the alert: `cat /tmp/watchdog-alert.json`
  2. Spawn a koder agent to fix the issue on SANDBOX
  3. Delete the file: `rm /tmp/watchdog-alert.json`
  4. Report: "🤖 Watchdog alert → agent dispatched"
- If NO: skip

## Agent Activity Monitor (THIRD PRIORITY)
- Run: `tail -5 /root/.openclaw/workspace/swarm/logs/$(date +%Y-%m-%d).jsonl 2>/dev/null`
- Check for NEW agent messages since last heartbeat (compare timestamps)
- If an agent reported "סיימתי" / "✅" / "done" / "הושלמה":
  1. Read the full message
  2. Report to Yossi in the relevant topic: "⚙️ [agent] סיים: [summary]"
  3. If peer-review is needed, trigger it
- Track last checked timestamp in `/tmp/heartbeat-agent-last.txt`

## Auto-Approve Handler
- If ANY recent message in General matches pattern `approve_XXXX`:
  - Run: `bash /root/.openclaw/workspace/swarm/handle-approve.sh XXXX`
- If pattern `reject_XXXX`:
  - Run: `send.sh or 1 "❌ PR #XXXX rejected"`

## Pieces LTM Sync (every heartbeat)
- Run: `bash /root/.openclaw/workspace/swarm/pieces-sync.sh`
- This syncs daily memory, git commits, agent activity, and MEMORY.md to Pieces

## Pieces Real-Time — MANDATORY on EVERY turn
- After EVERY reply to the user, save the exchange to Pieces:
  ```bash
  /root/.openclaw/workspace/swarm/pieces-realtime.sh "user:yossi" "USER_MESSAGE_SUMMARY"
  /root/.openclaw/workspace/swarm/pieces-realtime.sh "agent:or" "MY_REPLY_SUMMARY"
  ```
- Keep summaries short (1-2 lines), capture the essence
- This is how Pieces learns about our conversations in real-time

## Nothing else needed? → HEARTBEAT_OK
