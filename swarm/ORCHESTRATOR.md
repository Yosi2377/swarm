# ORCHESTRATOR.md — Swarm Orchestrator Protocol

## Core Architecture: Evaluator-Optimizer Pattern

Every task follows this flow:
```
Task → Agent works → Evaluator checks → PASS? → Report to Yossi
                                        → FAIL? → Agent retries (max 3x)
```

## Step-by-Step Flow

### 1. RECEIVE TASK
- Classify by domain (see routing table below)
- Create topic: `THREAD=$(bash swarm/create-topic.sh "emoji Task Name" "" agent_id)`

### 2. DISPATCH AGENT
- Generate task: `TASK=$(bash swarm/spawn-agent.sh agent_id $THREAD "task description")`
- Spawn: `sessions_spawn` with task=$TASK, label=agent_id-task-$THREAD

### 3. WAIT FOR COMPLETION
- Sub-agent announces when done (auto via sessions_spawn)
- wake-check.sh sends Telegram notification every 2 min

### 4. EVALUATE (MANDATORY — never skip!)
When agent reports done:
```bash
bash swarm/evaluate-agent.sh <agent_id> <thread_id> "task desc" <project_dir>
```
- PASS → proceed to step 5
- FAIL → steer agent to fix issues (max 3 retries), then re-evaluate

### 5. REPORT TO USER
- Send screenshot/evidence to Yossi
- Only say "done" after evaluation PASSES
- Never trust agent's self-report without evaluation

## Routing Table
| Domain | Agent | ID |
|--------|-------|----|
| Security, scanning | שומר | shomer |
| Code, bugs, API | קודר | koder |
| Design, UI, images | צייר | tzayar |
| Research, docs | חוקר | researcher |
| Testing, QA | בודק | bodek |
| Database, migrations | דאטא | data |
| Debug, errors, logs | דיבאגר | debugger |
| Docker, DevOps | דוקר | docker |
| Frontend, CSS, JS | פרונט | front |
| Backend, Node, API | באק | back |
| E2E, unit tests | טסטר | tester |
| Refactoring | ריפקטור | refactor |
| Monitoring, alerts | מוניטור | monitor |
| Performance | אופטימייזר | optimizer |
| Integrations, webhooks | אינטגרטור | integrator |
| Everything else | עובד | worker |

## IRON RULES
1. **NEVER report "done" to Yossi without running evaluate-agent.sh**
2. **NEVER let agents touch production directly**
3. **NEVER add tasks Yossi didn't ask for**
4. **ALWAYS respond immediately when Yossi messages**
5. **If agent fails 3 evaluations → report failure honestly, don't pretend it works**
