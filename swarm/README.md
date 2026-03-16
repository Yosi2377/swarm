# Swarm Scripts

Core scripts for the OpenClaw swarm orchestration system. 90 unused/duplicate scripts archived to `archive/`.

## Core Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `create-topic.sh` | Create Telegram forum topic | `create-topic.sh "name" [icon_color] [agent_id]` |
| `send.sh` | Send message as agent bot | `send.sh <agent_id> <thread_id> "message" [--photo path]` |
| `dispatch-task.sh` | Full dispatch with contract & reliability layer | `dispatch-task.sh <agent_id> <thread_id> "task" [project_dir]` |
| `verify-task.sh` | Independent verification (never trusts self-report) | `verify-task.sh <agent_id> <thread_id>` |
| `self-correct.sh` | Analyze failure & generate enriched retry prompt | `self-correct.sh <agent_id> <thread_id> [project_dir]` |
| `done-marker.sh` | Mark agent task as done | `done-marker.sh <label> <topic_id> "summary"` |
| `watchdog.sh` | Detect stuck agents (cron-compatible) | `watchdog.sh [max_minutes]` |
| `progress-report.sh` | Report agent progress (single event) | `progress-report.sh <agent_id> <thread_id> "message" [step]` |
| `delegate.sh` | Full delegation with structured schema + lessons | `delegate.sh <agent> "task" [keywords] [thread] [priority]` |
| `report-done.sh` | Screenshot + summary to topic | `report-done.sh <topic_id> "summary" [url]` |
| `screenshot.sh` | Multi-viewport screenshots to Telegram | `screenshot.sh <url> <thread_id> <agent_id> [label]` |

## Support Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `ask-help.sh` | Inter-agent help requests | `ask-help.sh <from> <to> <thread> "desc"` |
| `checkpoint.sh` | Durable execution: checkpoint + resume | `checkpoint.sh <task_id> <step>` |
| `episode.sh` | Save completed tasks as episodic memory | `episode.sh <agent_id> <thread_id>` |
| `pieces-realtime.sh` | Save event to Pieces LTM in real-time | `pieces-realtime.sh "source" "content"` |
| `pieces-save.sh` | Save task summary to Pieces LTM | `pieces-save.sh <agent_id> <thread_id> "summary"` |
| `pipeline.sh` | Chain agents: A→B→C | `pipeline.sh <pipeline-definition-file>` |
| `progress.sh` | Auto-report every 3 min (background) | `progress.sh <agent_id> <thread_id> "task" &` |
| `reflect.sh` | Structured reflection after failure | `reflect.sh <agent_id> <thread_id>` |
| `self-heal.sh` | Self-healing wrapper with retries | `self-heal.sh <max_retries> <command...>` |
| `update-status.sh` | Update agent status | `update-status.sh <agent> <task_id> <status> [desc]` |

## Engine

| Script | Purpose |
|--------|---------|
| `engine/learn.sh` | Learning engine — extract & store lessons from completed tasks |

## Archived

90 scripts moved to `archive/` (+ 16 engine scripts to `archive/engine/`). These were duplicates, unused, or superseded by the core scripts above.

## Cleanup History

- **2026-03-16**: Reduced from ~107 scripts to 21 + 1 engine. Archived 106 unused scripts.
