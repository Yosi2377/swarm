# ORCHESTRATOR.md — Swarm Orchestrator Protocol v2

## Core Principle: NEVER TRUST AGENT SELF-REPORTS

Every task follows this flow:
```
Task → Create Topic → Spawn Agent → Agent works → Agent reports done
  → ORCHESTRATOR VERIFIES INDEPENDENTLY → PASS? → Report to Yossi
                                         → FAIL? → Steer/retry (max 3x)
                                         → 3 FAILS? → Report failure honestly
```

## Step-by-Step Flow

### 1. RECEIVE TASK
- Classify by domain (see routing table)
- Create topic: `THREAD=$(bash swarm/create-topic.sh "emoji Task Name" "" agent_id)`

### 2. DISPATCH AGENT
- Generate task + save metadata:
  ```bash
  TASK=$(bash swarm/spawn-agent.sh agent_id $THREAD "task desc" "test_command" "project_dir")
  ```
- Spawn with timeout:
  ```bash
  sessions_spawn(task=$TASK, label=agent_id-$THREAD, runTimeoutSeconds=600)
  ```
- Default timeout: 600s (10 min). Complex tasks: 1800s (30 min).

### 3. AGENT COMPLETES (or times out)
- **Success:** Agent announces completion via system message
- **Timeout:** System reports timeout → treat as failure

### 4. VERIFY INDEPENDENTLY (MANDATORY — never skip!)
Run verification BEFORE reporting to Yossi:
```bash
bash swarm/verify-task.sh <agent_id> <thread_id>
```
This:
- Runs the actual test command
- Checks for failures in output (not just exit code)
- Cross-checks agent's self-report vs reality
- Flags if agent lied about results

### 5. REPORT TO YOSSI
- **PASS:** Report success with evidence
- **FAIL:** 
  - Attempt 1-2: Steer agent to fix (`subagents steer` or re-spawn)
  - Attempt 3: Report failure honestly. Do NOT pretend it works.

## IRON RULES

1. **NEVER report "done" without running verify-task.sh**
2. **NEVER trust agent's test count** — verify independently
3. **NEVER let agents touch production**
4. **NEVER add tasks Yossi didn't ask for**
5. **ALWAYS respond immediately when Yossi messages**
6. **ALWAYS set runTimeoutSeconds on sessions_spawn**
7. **If agent needs info it doesn't have → provide it via send.sh to their topic**

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

## Model Selection (Cost Control)
| Task Complexity | Model | Examples |
|----------------|-------|----------|
| Simple | sonnet | File edits, formatting, status checks |
| Standard | sonnet | Bug fixes, feature implementation, testing |
| Complex | opus | Architecture, debugging hard issues, security audit |

Default: sonnet. Use opus only for genuinely complex tasks.
Pass model parameter: `sessions_spawn(..., model="anthropic/claude-sonnet-4-20250514")`
