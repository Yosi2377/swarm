# HEARTBEAT.md

## 🔔 Sub-Agent Check (FIRST PRIORITY)
- Run sessions_list(kinds=["subagent"], activeMinutes=60, messageLimit=1)
- For each sub-agent that has a final message (stopReason="stop"):
  - Check if label was already reported: read swarm/memory/reported-spawns.json
  - If NOT reported:
    1. Read the result (last message)
    2. Run evaluator.sh if applicable
    3. Take screenshot if applicable  
    4. Post summary to General via send.sh or 1 "✅ [label] הושלם: [summary]"
    5. Add label to swarm/memory/reported-spawns.json
  - This prevents Yossi from asking "מה קורה?" — we report automatically!

## Delegation Queue
- Check /tmp/delegate-queue/ for pending .json files
- For each pending file: activate the target agent session via sessions_send
- Mark file as "activated" after sending
- This enables agent-to-agent delegation without orchestrator bottleneck

## Active Task Monitoring
- Check swarm/tasks.json for active tasks
- For each active task, check:
  1. Last update time (from task file `swarm/memory/task-<id>.md` mtime)
  2. Git activity: `git log --since='10 minutes ago' --oneline` in workspace
  3. Is progress.sh running? `pgrep -f "progress.sh .* <thread_id>"`
- If task active 10+ min with no updates:
  1. Send ping via `sessions_send` to `agent:main:telegram:group:-1003815143703:topic:<THREAD_ID>`
  2. Wait 2 min, check again
  3. If still no response → reactivate agent session with task context
  4. Send alert to General: `send.sh or 1 "⚠️ סוכן X תקוע ב-#Y — מפעיל מחדש"`
- If task stuck after reactivation → try to unblock or split
- Post status update to General if tasks changed

## Web Monitor
- Run: `cd skills/web-monitor && uv run --with beautifulsoup4 python scripts/monitor.py check`
- If 🔔 CHANGED or ❌ Error → alert Yossi: `send.sh or 1 "⚠️ ZozoBet שינוי/תקלה: ..."`
- If ✅ No changes → silent

## Learning Evolution
- Run `swarm/learn.sh evolve` to check for pattern-based skill generation
- Run `swarm/learn.sh report` to check agent scores
- If any agent score < 30%, flag it
