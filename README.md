# 🐝 Swarm — Multi-Agent Task System

A Telegram-based multi-agent orchestration system for managing tasks with specialized AI agents.

## Agents

| Agent | Role | Emoji |
|-------|------|-------|
| אור (Or) | Orchestrator | 🐝 |
| שומר (Shomer) | Security & Reviews | 🔒 |
| קודר (Koder) | Code & Deployment | ⚙️ |
| צייר (Tzayar) | Design & UI | 🎨 |
| עובד (Worker) | General Tasks | 🤖 |

## Features

- **Priority Queue** — Tasks with urgent/high/normal/low priority levels
- **Task Persistence** — Agents save state to survive timeouts
- **Code Review** — Shomer reviews all code changes (3-strike rollback)
- **Daily Summaries** — Automated daily activity reports
- **Auto Push** — Git commits auto-push to GitHub
- **Agent Chat** — Inter-agent collaboration channel

## Quick Start

```bash
# Add a task
./swarm/task.sh add koder 123 "Fix login bug" urgent

# Check status
./swarm/task.sh board

# Send daily summary
./swarm/daily-summary.sh

# Send as agent
./swarm/send.sh koder 123 "Working on it..."
```

## Structure

```
swarm/
├── ORCHESTRATOR.md   # Orchestrator instructions
├── SYSTEM.md         # Agent instructions
├── task.sh           # Task CLI
├── send.sh           # Telegram messaging
├── daily-summary.sh  # Daily reports
├── tasks.json        # Task state
├── agents.json       # Agent registry
├── templates/        # Task templates
├── memory/           # Persistent findings
└── logs/             # Message logs
```

<!-- Live test by Koder ⚙️ — 2026-02-12 -->
