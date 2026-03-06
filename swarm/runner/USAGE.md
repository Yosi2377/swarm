# Agent Runner — How to Use

## For Orchestrator (Or):

### Step 1: Dispatch task
```
1. Create topic: THREAD=$(swarm/create-topic.sh "emoji Task" "" agent_id | tail -1)
2. Save metadata:
   mkdir -p /tmp/agent-tasks
   echo '{"agent_id":"<id>","thread_id":"<thread>","url":"<url>","test_cmd":"<test>","project_dir":"<dir>","status":"running","retries":0}' > /tmp/agent-tasks/<id>-<thread>.json
3. Generate task: TASK=$(swarm/spawn-agent.sh <id> <thread> "task" "test_cmd" "project_dir")
4. Send to topic: swarm/send.sh <id> <thread> "📋 task..."
5. Spawn: sessions_spawn(task=$TASK)
```

### Step 2: When agent reports done (via heartbeat/subagent completion)
```bash
node swarm/runner/verify-and-report.js <agent_id> <thread_id> \
  --url "https://..." \
  --test "npm test" \
  --project "/root/Project"
```

### Step 3: Handle result
- Exit 0 (PASS) → Report to Yossi with screenshot
- Exit 1 (RETRY) → Re-spawn agent with error feedback (auto-sent to topic)
- Exit 2 (ESCALATE) → Tell Yossi honestly

## What verify-and-report.js checks:
1. ✅ Agent report exists
2. ✅ Tests pass (if test command provided)
3. ✅ URL returns 200
4. ✅ Page loads correctly (with login, not error/blank)
5. ✅ Screenshot is valid (not blank)
6. ✅ Git is clean
