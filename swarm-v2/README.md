# swarm-v2 — Simple Agent System

Lightweight agent runner with real verification.

## Scripts

| Script | Usage | Description |
|--------|-------|-------------|
| `agent-runner.sh` | `<agent_id> <thread_id> <task> [project_dir] [--dry-run]` | Build prompt, notify Telegram, output task for spawning |
| `verify.sh` | `<agent_id> <thread_id> [project_dir]` | Check done marker + git commit + screenshot, send results |
| `orchestrate.sh` | `<task_description> [project_dir] [--dry-run]` | Auto-route task to agent, create topic, run |
| `monitor-daemon.sh` | `[--once]` | Background loop checking /tmp/agent-done/ for new results |

## How It Works

1. **orchestrate.sh** picks the right agent by keywords
2. **agent-runner.sh** builds a short prompt (<40 lines) and notifies Telegram
3. Agent runs via `sessions_spawn` with the generated prompt
4. Agent writes result to `/tmp/agent-done/<agent>-<thread>.json`
5. **verify.sh** checks: done marker exists? git commit? screenshot?
6. **monitor-daemon.sh** auto-catches completed agents

## Done Marker Format

```json
{"status": "done", "summary": "what was done", "screenshot": "/tmp/agent-X-Y.png"}
```

## Key Directories

- `/tmp/agent-tasks/` — saved prompts
- `/tmp/agent-done/` — agent results (JSON)
- `/tmp/agent-verified/` — already-verified markers
