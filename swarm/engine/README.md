# Swarm Engine

Production-ready agent orchestration system for the TeamWork swarm.

## Architecture

```
orchestrate.sh  →  creates topic, builds prompt, outputs JSON
     ↓
auto-loop.sh    →  polls for .done, runs checks, signals retries
     ↓
monitor.sh      →  background daemon tracking all tasks
     ↓
escalate.sh     →  handles failures after max retries
     ↓
learn.sh        →  saves/queries lessons from past tasks
```

## Scripts

### `orchestrate.sh "task" [project_dir] [url]`
Main entry point. Classifies task → agent, queries lessons, creates Telegram topic, builds prompt, outputs JSON for the caller.

### `auto-loop.sh <agent> <thread> <prompt_file> <check_cmd> [max_retries]`
Retry loop. Waits for `.done` marker, runs check command, enriches prompt on failure, writes `-retry.json` for orchestrator to re-spawn.

### `learn.sh {save|query|inject} ...`
- `save <agent> <task> <pass|fail> <lesson>` — store a lesson
- `query <keywords> [max]` — search lessons
- `inject <agent> <task_desc>` — get relevant lessons for prompt injection

### `escalate.sh <agent> <thread> <task> <errors>`
Decides: reassign to fallback agent, simplify task, or report failure. Writes `-escalation.json`.

### `monitor.sh [interval]`
Background daemon. Scans `/tmp/engine-tasks/` and `/tmp/engine-steps/` every N seconds. Writes `/tmp/engine-status.json`.

### `status.sh`
Human-readable status of all tasks. Run anytime.

### `check.sh <type> <args...>`
7 verification types: `http_status`, `screenshot`, `git_changed`, `grep_content`, `test_run`, `process_running`, `file_exists`.

## File Conventions

| Path | Purpose |
|------|---------|
| `/tmp/engine-tasks/{agent}-{thread}.prompt` | Task prompt |
| `/tmp/engine-tasks/{agent}-{thread}-meta.json` | Task metadata |
| `/tmp/engine-tasks/{agent}-{thread}-retry.json` | Retry signal |
| `/tmp/engine-tasks/{agent}-{thread}-escalation.json` | Escalation decision |
| `/tmp/engine-steps/{agent}-{thread}.done` | Completion marker |
| `/tmp/engine-status.json` | Monitor status output |
| `engine/lessons.json` | Learning database |

## Flow

1. Caller runs `orchestrate.sh "fix the login page" /root/BotVerse http://localhost:3200`
2. Gets JSON back with agent, thread, prompt_file, check command
3. Spawns sub-agent with the prompt
4. Optionally runs `auto-loop.sh` for retry logic
5. `monitor.sh` tracks everything in background
6. On failure after retries → `escalate.sh` decides next step
7. `learn.sh save` records lessons for future tasks
