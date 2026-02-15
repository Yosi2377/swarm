# Swarm Dashboard — מבנה + API

## Overview
Dashboard לניטור סוכני ה-Swarm — משימות, סוכנים, לוגים, ציונים, timeline.

## Service
- **Port**: 8090
- **Service**: `swarm-dashboard`
- **Path**: `/root/.openclaw/workspace/swarm/dashboard/`
- **Stack**: Node.js + Express + Chokidar (file watching) + SSE

## Data Sources (files, not DB)
| Data | File | Format |
|------|------|--------|
| Tasks | `swarm/tasks.json` | JSON: {tasks[], completed[]} |
| Task details | `swarm/tasks/*.md` | Markdown per task |
| Agents | `swarm/agents.json` | JSON: {agents: {id: {...}}} |
| Active context | `swarm/memory/shared/active-context.md` | Markdown table |
| Scores | `swarm/learning/scores.json` | JSON: {agents: {id: {score, tasks, success, fail, streak}}} |
| Lessons | `swarm/learning/lessons.json` | JSON: {lessons: [{timestamp, agent, lesson}]} |
| Quality | `swarm/learning/quality.json` | JSON: {reviews[], agentAverages: {}} |
| Logs | `swarm/logs/YYYY-MM-DD.jsonl` | JSONL: {timestamp, agent, thread, message} |
| Sessions | `/root/.openclaw/agents/main/sessions/sessions.json` | Live session data |

## API Endpoints

### Core
- `GET /api/tasks` → {tasks[], completed[]} — merged from tasks.json + tasks/*.md
- `GET /api/agents` → {id: {name, emoji, role, status, task, score, ...}} — merged from agents.json + active-context.md + scores.json
- `GET /api/agents/live` → [{key, name, emoji, status, currentTask, model, tokens, ageMinutes, ...}] — live sessions from sessions.json

### Timeline & Logs
- `GET /api/timeline` → [{type, timestamp, agent, message, ...}] — git + logs + completed tasks + lessons (last 200)
- `GET /api/logs?date=YYYY-MM-DD` → [{timestamp, agent, thread, message}] — raw log entries
- `GET /api/log-dates` → ["2026-02-15", ...] — available log dates

### Learning
- `GET /api/scores` → {agentId: {score, tasks, success, fail, streak}}
- `GET /api/lessons` → [{timestamp, agent, lesson}]
- `GET /api/quality` → {reviews[], agentAverages: {}}

### Other
- `GET /api/active-context` → {content: "markdown string"}
- `GET /api/task-files` → [{id, title, agent, status, priority, ...}] — legacy
- `GET /api/stream` → SSE stream (events: tasks, agents, scores, lessons, timeline, live)
- `GET /api/events` → SSE stream (legacy alias)

### SSE Events
Real-time updates via Server-Sent Events. Types:
- `connected` — initial connection
- `tasks` — tasks.json or tasks/*.md changed
- `agents` — active-context.md changed
- `scores` — scores.json changed
- `lessons` — lessons.json changed
- `timeline` — logs changed
- `live` — sessions.json changed
- `update` — generic

## File Structure
```
/root/.openclaw/workspace/swarm/dashboard/
  server.js          -- Express server (8090)
  public/
    index.html       -- Dashboard SPA (all frontend in one file)
  package.json       -- deps: express, chokidar
```

## Agent ID Mapping
| ID | Name | Emoji | Role |
|----|------|-------|------|
| or | אור | ✨ | orchestrator |
| shomer | שומר | 🔒 | security |
| koder | קודר | ⚙️ | coding |
| tzayar | צייר | 🎨 | design |
| worker | עובד | 🤖 | worker |
| researcher | חוקר | 🔍 | research |

## Common Mistakes
- ❌ Looking for a database → ✅ Dashboard reads **files only** (JSON, JSONL, Markdown)
- ❌ Editing sessions.json directly → ✅ It's managed by OpenClaw
- ❌ Forgetting to restart service → ✅ `systemctl restart swarm-dashboard`
- ❌ Changing port → ✅ Must also update nginx config
