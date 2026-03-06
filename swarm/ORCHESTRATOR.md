# ORCHESTRATOR.md — SwarmClaw Orchestrator Protocol v4

## Core Principle: NEVER TRUST AGENT SELF-REPORTS

```
Task → SwarmClaw analyzes → Split if needed → Create Topics → Spawn Agents
  → Agent works → Reports done → SwarmClaw Evaluator verifies
  → PASS → Report to Yossi (with independent screenshot)
  → FAIL → Auto-retry with feedback (max 3x)
  → 3 FAILS → Escalate honestly
```

## Flow

### 1. RECEIVE TASK — Analyze & Route
```bash
# SwarmClaw analyzes the task, detects project, suggests split:
PLAN=$(bash /root/SwarmClaw/core/prepare-task.sh "task description" [project])
# Returns: { single: {agent, project}, autoSplit: [{agent, desc}, ...] }
```

**Decision:**
- **autoSplit has items?** → Create topic per sub-task, spawn in parallel
- **Single task?** → Create one topic, spawn one agent
- **Complex/unclear?** → Use splitPrompt with LLM to decide split

### 2. CREATE TOPICS & DISPATCH
For each (sub-)task:
```bash
# Create topic:
THREAD=$(bash swarm/create-topic.sh "emoji Task Name" "" agent_id)

# Generate task text (SwarmClaw injects project context automatically):
TASK=$(bash swarm/spawn-agent.sh agent_id $THREAD "task desc" "test_cmd" "project_dir")

# Send to topic:
bash swarm/send.sh agent_id $THREAD "📋 משימה: ..."

# Spawn:
sessions_spawn(task=$TASK, label="agent_id-$THREAD", runTimeoutSeconds=600)
```

### 3. AGENT COMPLETES → EVALUATE
When agent reports done (heartbeat or subagent completion):
```bash
# SwarmClaw evaluator runs automatically (via on-agent-done.sh):
bash /root/SwarmClaw/core/run-evaluator.sh agent_id thread_id project_name
# Checks: git commits, tests, URL, service
# Returns: PASS / RETRY / ESCALATE
```

### 4. REPORT TO YOSSI
- **PASS** → Send summary + independent screenshot to General
- **RETRY** → Agent gets detailed feedback, tries again
- **ESCALATE** → Tell Yossi honestly what failed

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
- **3+ comma-separated items** → Auto-split to different agents
- **"build/fix X"** → Agent builds + tester verifies
- **Complex/ambiguous** → Use LLM split prompt
- **Simple single task** → One agent, no split
- **Dependencies** → "after" field, dispatch sequentially

## Project Detection
- "botverse" / "bot verse" → botverse
- "betting" / "zozo" / "הימור" → betting  
- "poker" / "פוקר" / "texas" → poker
- Default → botverse

## Dashboard
- **URL:** http://95.111.247.22:4500
- Shows all agents, tasks, verifications, performance charts
- Auto-refreshes every 15 seconds

## Iron Rules
1. **NEVER fix code yourself** — always through agents
2. **NEVER trust agent claims** — evaluator verifies independently  
3. **NEVER skip topic creation** — every task gets its own topic
4. **ALWAYS use prepare-task.sh** — for routing and splitting
5. **ALWAYS report honestly** — if it failed, say it failed
