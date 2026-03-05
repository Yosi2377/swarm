# SYSTEM.md — Agent Protocol v5 (Simplified)

## You Are a Task Agent
Work in TeamWork group `-1003815143703`. Each task = own topic.

## Communication
```bash
# Send message to your topic:
/root/.openclaw/workspace/swarm/send.sh <your_agent_id> <thread_id> "message"

# Your session messages are NOT visible! Only send.sh posts are.
```

## 3 Rules — Break Any = Failure

### 1. VERIFY BEFORE "DONE"
```bash
# Run this BEFORE reporting done:
bash /root/.openclaw/workspace/swarm/verify-before-done.sh
```
- If server is down → fix it
- If tests fail → fix them
- If DB counts dropped → restore backup
- **No green verify = no "done" report**

### 2. PROOF — Screenshots Required
Take screenshot + send to your topic BEFORE reporting done.

### 3. REPORT DONE — Direct to Telegram
When finished, send BOTH:
```bash
# To your topic:
/root/.openclaw/workspace/swarm/send.sh <your_agent_id> <thread_id> "✅ הושלם: [summary]"
# To General (topic 1):
/root/.openclaw/workspace/swarm/send.sh or 1 "✅ [YOUR_LABEL] הושלם: [one line summary]"
```

## Workflow
1. **Read task** → understand what's needed
2. **Research** → `web_search` if unsure
3. **Implement** → write code
4. **Test** → run tests, check with curl/browser
5. **Verify** → `verify-before-done.sh` must pass
6. **Report** → screenshots + summary via send.sh

## BotVerse Specific
- **Path:** /root/BotVerse
- **Restart:** `systemctl restart botverse && sleep 3`
- **E2E tests:** `bash /root/BotVerse/tests/e2e.sh`
- **DB backup before delete:** `bash /root/BotVerse/scripts/pre-agent-backup.sh`
- **NEVER** use `deleteMany({})` on: agents, skills, posts, owners

## Learning
```bash
swarm/learn.sh query "keywords"     # Before starting
swarm/learn.sh lesson <agent> <severity> "what" "learned"  # After
```

## Git Commit
```bash
cd /root/BotVerse && git add -A && git commit -m "#THREAD: description"
```

## Stuck?
- Failed 2x on same error → `web_search` for solution
- Need another agent → post to Agent Chat (topic 479)
