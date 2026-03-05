# ORCHESTRATOR.md — Swarm Orchestrator Protocol v3

## Core Principle: NEVER TRUST AGENT SELF-REPORTS

## Architecture Overview
```
Yossi → Orchestrator (Or) → Classify → Create Topic → Spawn Agent
                                                          ↓
                                          smart-eval.sh (background)
                                              ↓ polls every 15s
                                          Agent finishes
                                              ↓
                                          Hook Eval Agent (strict reviewer)
                                              ↓
                                          JSON Report + Telegram
                                              ↓
                                    PASS? → Done  |  FAIL? → Retry (max 2)
                                                           → Escalate to Yossi
```

## Step-by-Step Flow

### 1. RECEIVE TASK
- Classify by domain (see routing table below)
- Create topic: `THREAD=$(bash swarm/create-topic.sh "emoji Task Name" "" agent_id)`

### 2. DISPATCH AGENT
```bash
# Generate task prompt
TASK=$(bash swarm/spawn-agent.sh agent_id $THREAD "task desc" "test_command" "project_dir")

# Spawn with timeout
sessions_spawn(task=$TASK, label="agent_id-taskname", runTimeoutSeconds=180)

# Attach smart monitoring pipeline
bash swarm/spawn-task.sh "agent_id-taskname" "$THREAD" "task desc" "eval instructions" 180
```

### 3. AUTOMATIC MONITORING (smart-eval.sh)
smart-eval runs in background:
- Polls sessions.json every 15 seconds
- Detects completion when session stops updating (3 checks = 45s stable)
- On timeout: notifies and evaluates anyway
- Triggers strict evaluation via /hooks/agent-watcher

### 4. STRICT EVALUATION (eval-prompt.md)
Hook eval agent does:
- Runs tests independently (never trusts self-report)
- Reads actual code changes
- Checks for hardcoded/fake data
- Checks for modified test files
- Writes structured JSON report to /tmp/agent-reports/<label>.json
- Sends Hebrew report to Telegram topic

### 5. AUTO-RETRY ON FAILURE
- FAIL/SUSPECT → retry file created at /tmp/retry-request-<label>.json
- Retry 1: Re-spawn with issues from previous attempt
- Retry 2: Re-spawn with more context
- After 2 retries: ESCALATE to Yossi with full details

### 6. PIPELINE CHAINING (multi-step)
When task needs multiple agents (e.g., koder → shomer → tzayar):
1. Spawn step 1 with smart-eval
2. When step 1 report = PASS → spawn step 2
3. Check /tmp/agent-reports/<label>.json in heartbeat or after notification
4. Each step gets its own topic + smart-eval

## Scripts Reference
| Script | Purpose |
|--------|---------|
| `create-topic.sh` | Create Telegram topic for task |
| `spawn-agent.sh` | Generate task prompt with context |
| `spawn-task.sh` | Attach smart-eval monitoring to spawn |
| `smart-eval.sh` | Poll → detect done → strict eval → retry |
| `eval-prompt.md` | Strict reviewer instructions |
| `send.sh` | Send message as specific bot |
| `status.sh` | Dashboard: agents, monitors, reports, retries |
| `verify-before-done.sh` | Manual verification helper |
| `inject-lessons.sh` | Add relevant past lessons to task |

## Dashboard
```bash
bash swarm/status.sh        # Full status
bash swarm/status.sh 60     # Last 60 minutes
```

## IRON RULES

1. **NEVER report "done" without smart-eval verification**
2. **NEVER trust agent's test count** — eval agent re-runs tests
3. **NEVER let agents touch production**
4. **NEVER add tasks Yossi didn't ask for**
5. **ALWAYS respond immediately when Yossi messages**
6. **ALWAYS set runTimeoutSeconds on sessions_spawn** (default 180)
7. **ALWAYS attach smart-eval via spawn-task.sh after sessions_spawn**
8. **If agent needs info → provide via send.sh to their topic**

## Timeouts
| Task Type | Timeout | Examples |
|-----------|---------|----------|
| Simple fix | 120s | Typo, config change |
| Standard | 180s | Bug fix, feature |
| Complex | 300s | Architecture, multi-file |
| Very complex | 600s | Full feature, security audit |

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
