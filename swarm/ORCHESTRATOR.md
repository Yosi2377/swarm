# ORCHESTRATOR.md — Swarm Orchestrator Protocol v3 (FINAL)

## Core Principle: NEVER TRUST AGENT SELF-REPORTS

```
Task → Create Topic → Spawn Agent → Agent works → Agent reports done
  → on-agent-done.sh VERIFIES → PASS? → Report to Yossi
                                → FAIL? → Auto-retry (max 3x)
                                → 3 FAILS? → Escalate to Yossi honestly
```

## Complete Flow

### 1. RECEIVE TASK
```bash
# Classify by domain → pick agent_id from routing table
# Create topic:
THREAD=$(bash swarm/create-topic.sh "emoji Task Name" "" agent_id)
```

### 2. DISPATCH AGENT
```bash
# Generate task text (auto-saves metadata to /tmp/agent-tasks/):
TASK=$(bash swarm/spawn-agent.sh agent_id $THREAD "task desc" "test_command" "project_dir")

# Send task to topic:
bash swarm/send.sh agent_id $THREAD "📋 משימה: ..."

# Spawn with timeout:
sessions_spawn(task=$TASK, label=agent_id-$THREAD, runTimeoutSeconds=600)
```

### 3. AGENT COMPLETES
When system message announces completion:

### 4. VERIFY (AUTOMATIC — never skip!)
```bash
# Run independent verification:
bash swarm/on-agent-done.sh agent_id $THREAD "test_command" "project_dir"
```
This script:
- Runs tests independently (ignores what agent claims)
- Checks for structured completion report
- Cross-checks agent claims vs reality (catches lies)
- On PASS → outputs RESULT=PASS
- On FAIL → auto-sends retry instructions to agent topic, outputs RESULT=RETRY
- On 3rd fail → outputs RESULT=ESCALATE

### 5. REPORT TO YOSSI
- **PASS:** Report success with verify evidence
- **RETRY:** Re-spawn agent with failure details (automatic)
- **ESCALATE:** Tell Yossi honestly: "3 retries failed, here's what's wrong"

## Agent Communication Flow
```
Agent stuck → sends to Agent Chat (479) via send.sh
Orchestrator → sees in heartbeat or system message
Orchestrator → sends answer to agent's topic via send.sh
Agent → continues work with new info
```

## IRON RULES
1. **NEVER report "done" without running on-agent-done.sh**
2. **NEVER trust agent's test count** — verify independently
3. **NEVER let agents touch production**
4. **NEVER add tasks Yossi didn't ask for**
5. **ALWAYS respond immediately when Yossi messages**
6. **ALWAYS set runTimeoutSeconds on sessions_spawn** (default: 600)
7. **ALWAYS create a NEW topic per task** — never reuse topics

## Routing Table
| Domain | Agent | ID | Emoji |
|--------|-------|----|-------|
| Security, scanning | שומר | shomer | 🔒 |
| Code, bugs, API | קודר | koder | ⚙️ |
| Design, UI, images | צייר | tzayar | 🎨 |
| Research, docs | חוקר | researcher | 🔍 |
| Testing, QA | בודק | bodek | 🧪 |
| Database, migrations | דאטא | data | 📊 |
| Debug, errors, logs | דיבאגר | debugger | 🐛 |
| Docker, DevOps | דוקר | docker | 🐳 |
| Frontend, CSS, JS | פרונט | front | 🖥️ |
| Backend, Node, API | באק | back | ⚡ |
| E2E, unit tests | טסטר | tester | 🧪 |
| Refactoring | ריפקטור | refactor | ♻️ |
| Monitoring, alerts | מוניטור | monitor | 📡 |
| Performance | אופטימייזר | optimizer | 🚀 |
| Integrations, webhooks | אינטגרטור | integrator | 🔗 |
| Everything else | עובד | worker | 🤖 |

## Timeouts
| Task Type | Timeout |
|-----------|---------|
| Simple fix (1-2 files) | 300s (5 min) |
| Standard feature | 600s (10 min) |
| Complex / multi-file | 1200s (20 min) |
| Research / analysis | 1800s (30 min) |

## Scripts Reference
| Script | Purpose |
|--------|---------|
| `create-topic.sh` | Create new Telegram topic |
| `send.sh` | Send message as specific bot |
| `spawn-agent.sh` | Generate task text + save metadata |
| `verify-task.sh` | Independent test verification |
| `on-agent-done.sh` | Full post-completion pipeline |
| `done-marker.sh` | Agent marks itself done |
| `dispatch-task.sh` | Create topic + send + generate task (all-in-one) |
