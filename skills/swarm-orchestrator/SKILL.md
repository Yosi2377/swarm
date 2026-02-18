---
name: swarm-orchestrator
description: Multi-agent task orchestration system for Telegram forum groups. Route tasks to specialized agents (security, coding, design, research, QA), manage topics, coordinate dependencies, track progress with learning system. Use when managing a team of AI agents, delegating tasks, running parallel work, or coordinating multi-step projects.
---

# Swarm Orchestrator

Manage a team of AI sub-agents in a Telegram forum group. Each agent has a dedicated bot identity and topic.

## Agent Routing

| Domain | Agent | Emoji |
|--------|-------|-------|
| Security, scanning, SSL | shomer | 🔒 |
| Code, bugs, API, deploy | koder | ⚙️ |
| Design, UI, images | tzayar | 🎨 |
| Research, best practices | researcher | 🔍 |
| Testing, QA, regression | bodek | 🧪 |
| Everything else | worker | 🤖 |

## Task Flow

1. **Classify** — identify domain, split multi-domain tasks
2. **Query lessons** — `learn.sh query "keywords"` before sending
3. **Create topic** — Telegram forum topic with emoji prefix
4. **Send task** via `send.sh <agent> <topic_id> "instructions + injected lessons"`
5. **Activate agent** via `sessions_spawn` with full context
6. **Monitor** — supervisor cron checks every 60s
7. **Report** — screenshot FIRST, then text summary

## Scripts

| Script | Purpose |
|--------|---------|
| `send.sh <agent> <topic> <msg>` | Send as specific bot to topic |
| `learn.sh query/lesson/score` | Learning system |
| `prepare-task.sh "keywords"` | Query lessons for injection |
| `report-done.sh <topic> <summary>` | Screenshot + report |
| `pipeline.sh <step> <task-id>` | Track task pipeline |
| `deploy.sh` | Safe deploy with chattr protection |
| `evaluator.sh <project> <thread>` | Auto-evaluate with browser tests |

## Learning System

Agents accumulate lessons from successes/failures:
```bash
learn.sh query "relevant keywords"  # Before task
learn.sh lesson <agent> <severity> "title" "description"  # After task
learn.sh score <agent> success|fail  # Track scores
learn.sh report  # Show all scores
```

**Critical**: Orchestrator must query AND inject lessons into task prompts. Agents skip query on their own.

## Pipeline Enforcement

Production files locked with `chattr +i`. Only `deploy.sh` can unlock:
1. Sandbox development → 2. Browser tests → 3. Yossi approval → 4. Deploy

## Supervisor (Cron)

Runs every 60s, reports:
- 🟢 Agent started
- 🔄 Agent running X minutes  
- ✅ Agent finished (+ screenshot)
- ⚠️ Agent stuck 10+ minutes
