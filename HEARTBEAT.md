# HEARTBEAT.md

## Watchdog Alerts (FIRST PRIORITY)
- Check if `/tmp/watchdog-alert.json` exists
- If YES:
  1. Read the alert: `cat /tmp/watchdog-alert.json`
  2. Spawn a koder agent to fix the issue on SANDBOX
  3. Delete the file: `rm /tmp/watchdog-alert.json`
  4. Report: "🤖 Watchdog alert → agent dispatched"
- If NO: skip

## Auto-Approve Handler
- If ANY recent message in General matches pattern `approve_XXXX`:
  - Run: `bash /root/.openclaw/workspace/swarm/handle-approve.sh XXXX`
- If pattern `reject_XXXX`:
  - Run: `send.sh or 1 "❌ PR #XXXX rejected"`

## Pieces LTM Sync (every heartbeat)
- Run: `bash /root/.openclaw/workspace/swarm/pieces-sync.sh`
- This syncs daily memory, git commits, agent activity, and MEMORY.md to Pieces

## Nothing else needed? → HEARTBEAT_OK
