# ORCHESTRATOR.md — SwarmClaw Orchestrator Protocol v5

## IRC Mode Override
When `swarm/runtime.json` sets `transport=irc`:
- do not treat `thread_id` as a Telegram topic
- `create-topic.sh` returns an internal `job-*` id
- `#myops` is the orchestrator/control room
- `#agent-chat` is the visible inter-agent coordination room
- real task/work questions in `#myops` must open a `job-*` and be delegated
- small jobs may still report status in `#myops`, but the work itself should live in a `job-*` when delegation is needed
- bigger jobs are promoted to dedicated channels like `#job-0007`
- all summaries must return to `#myops`
- if a dependency/help handoff is needed, use `#agent-chat` visibly

## Core Principle: NEVER TRUST AGENT SELF-REPORTS
## Core Change v5: USE RUNNER, NOT RAW SPAWN

```
Task → Analyze & Route → dispatch.sh handles EVERYTHING:
  → Creates topic → Spawns agent → Waits → Verifies INDEPENDENTLY
  → PASS: sends screenshot + report to General
  → FAIL: auto-retries with specific error feedback (max 3x)  
  → 3 FAILS: escalates honestly to Yossi
```

## How to Dispatch (THE ONLY WAY)

### Option A: From Orchestrator (Or) via sessions_spawn
```bash
TASK=$(cat <<'EOF'
Run the agent runner for this task:
node /root/.openclaw/workspace/swarm/runner/agent-runner.js \
  --agent koder \
  --task "fix the GitHub OAuth button" \
  --url "https://botverse.dev/dashboard.html" \
  --test "cd /root/BotVerse && node tests/e2e.js" \
  --project "/root/BotVerse"
EOF
)
sessions_spawn(task=$TASK, label="runner-koder-github")
```

### Option B: Direct CLI
```bash
bash /root/.openclaw/workspace/swarm/runner/dispatch.sh koder \
  "fix the GitHub OAuth button" \
  --url "https://botverse.dev/dashboard.html" \
  --test "cd /root/BotVerse && node tests/e2e.js" \
  --project "/root/BotVerse"
```

## What the Runner Does (you don't need to do these manually anymore):
1. ✅ Creates Telegram topic
2. ✅ Sends task to agent
3. ✅ Spawns sub-agent with focused instructions
4. ✅ Waits for completion
5. ✅ Takes its OWN screenshot (not the agent's!)
6. ✅ Verifies URL returns 200
7. ✅ Checks page isn't login/error/blank
8. ✅ Verifies pixel content of screenshot
9. ✅ Runs test command independently
10. ✅ Checks git is committed
11. ✅ If FAIL → sends specific errors to agent → auto-retry
12. ✅ If PASS → sends screenshot + summary to General
13. ✅ If 3 FAILS → escalates to Yossi

## ⛔ NEVER DO THIS ANYMORE:
- ❌ `sessions_spawn` directly with task text
- ❌ `spawn-agent.sh` without the runner
- ❌ Trust agent's "✅ הושלם" without runner verification
- ❌ Send "done" to Yossi without runner's independent screenshot

## Agent Routing Table
| Domain | Agent | Emoji |
|--------|-------|-------|
| Code, bugs, API | koder | ⚙️ |
| Security, audit | shomer | 🔒 |
| Design, UI, CSS | tzayar | 🎨 |
| Research | researcher | 🔍 |
| Testing, QA | tester | 🧪 |
| Database, MongoDB | data | 📊 |
| Debug, errors | debugger | 🐛 |
| Docker, DevOps | docker | 🐳 |
| Frontend, HTML/JS | front | 🖥️ |
| Backend, Express | back | ⚡ |
| Refactoring | refactor | ♻️ |
| Monitoring | monitor | 📡 |
| Performance | optimizer | 🚀 |
| Integrations, OAuth | integrator | 🔗 |
| General / catch-all | worker | 🤖 |

## Task Splitting Rules
- **3+ comma-separated items** → Auto-split, dispatch.sh per sub-task
- **Complex/ambiguous** → Split manually, one dispatch.sh per part
- **Simple single task** → One dispatch.sh call

## Iron Rules
1. **ALWAYS use dispatch.sh or agent-runner.js** — never raw spawn
2. **NEVER trust agent claims** — runner verifies independently
3. **NEVER skip --url** — if task has a web component, pass the URL
4. **NEVER skip --test** — if task has tests, pass the test command
5. **ALWAYS report honestly** — if runner says FAIL, tell Yossi it failed
