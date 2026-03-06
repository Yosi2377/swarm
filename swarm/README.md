# 🐝 SwarmClaw — Autonomous AI Agent Orchestration System

**Multi-agent task automation with independent verification, self-healing retries, and Telegram-native coordination.**

SwarmClaw transforms a single AI session into a coordinated team of specialized agents — each with its own identity, expertise, and accountability.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    TELEGRAM GROUP                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │ General  │ │ Task #1 │ │ Task #2 │ │ Task #N │   │
│  │ (topic)  │ │ (topic) │ │ (topic) │ │ (topic) │   │
│  └────▲─────┘ └────▲────┘ └────▲────┘ └────▲────┘   │
└───────┼────────────┼──────────┼──────────┼───────────┘
        │            │          │          │
┌───────┴────────────┴──────────┴──────────┴───────────┐
│                   ORCHESTRATOR (אור)                  │
│                                                       │
│  dispatch.sh ──► create-topic ──► spawn-agent         │
│       │              │                │               │
│       ▼              ▼                ▼               │
│  ┌─────────┐  ┌──────────┐   ┌────────────┐         │
│  │ Metadata │  │ Queue    │   │ Task Text  │         │
│  │ /tmp/    │  │ /tmp/    │   │ + Lessons  │         │
│  │ agent-   │  │ dispatch-│   │ + Context  │         │
│  │ tasks/   │  │ queue/   │   └────────────┘         │
│  └─────────┘  └─────┬────┘                           │
│                      │                                │
│              ┌───────▼────────┐                       │
│              │ dispatch-      │  ◄── runs every 1min  │
│              │ watcher.sh     │      (cron)           │
│              └──┬──────┬──┬──┘                        │
│                 │      │  │                            │
│     ┌──────────┘      │  └──────────┐                │
│     ▼                 ▼             ▼                 │
│  ┌──────┐      ┌──────────┐   ┌─────────┐           │
│  │Spawn │      │ Verify   │   │ Stuck   │           │
│  │Agent │      │ & Report │   │ Check   │           │
│  │(hook)│      │ (node.js)│   │ (>15m)  │           │
│  └──┬───┘      └────┬─────┘   └────┬────┘           │
│     │               │              │                  │
│     ▼               ▼              ▼                  │
│  ┌──────┐    ┌────────────┐  ┌──────────┐           │
│  │OpenClaw   │ PASS→General  │ Escalate │           │
│  │Sub-agent  │ FAIL→Retry(3) │ to Human │           │
│  └──────┘    │ ESC→Human  │  └──────────┘           │
│              └────────────┘                           │
└───────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              VERIFICATION PIPELINE                    │
│                                                       │
│  1. Report exists?          (structured JSON)         │
│  2. Tests pass?             (custom test command)     │
│  3. URL responds?           (HTTP status check)       │
│  4. Page renders?           (Puppeteer + login)       │
│  4b. Expected content?      (--expect "text")         │
│  5. Screenshot valid?       (pixel variance check)    │
│  6. Git committed?          (clean working tree)      │
│                                                       │
│  PASS  → Screenshot proof to General + score update   │
│  FAIL  → Retry with error feedback (up to 3x)        │
│  ESCALATE → Notify human with full issue list         │
└─────────────────────────────────────────────────────┘
```

## How It Works

### 1. Dispatch
```bash
# One command does everything
bash swarm/runner/dispatch.sh koder "Fix login bug on /admin" \
    --url https://mysite.com/admin \
    --test "npm test" \
    --project /root/MyProject \
    --expect "Login successful"
```

This:
- Creates a dedicated Telegram topic with agent-colored icon
- Generates task instructions with injected past lessons
- Sends the task to the topic as the agent's bot
- Writes metadata for tracking
- Queues for automatic agent spawning

### 2. Automatic Spawning
The `dispatch-watcher.sh` (runs every minute via cron):
- Picks up queued tasks
- Spawns OpenClaw sub-agents via webhook
- Falls back to heartbeat pickup if hook fails

### 3. Agent Execution
Each agent runs in isolation with:
- Full tool access (browser, shell, file system)
- Project-specific context and config
- Past lessons from the learning system
- Clear verification expectations

### 4. Independent Verification
When an agent reports done, the verification pipeline:
- Runs tests independently (not trusting the agent)
- Checks URLs and page rendering
- Validates expected content on page
- Takes independent screenshots
- Checks git history for real commits

### 5. Self-Healing
- **PASS** → Proof sent to General, scores updated
- **FAIL** → Agent gets specific error feedback, auto-retried (up to 3x)
- **ESCALATE** → Human notified with full issue list
- **STUCK** → Flagged after 15 minutes of inactivity

---

## Agent Types

| Agent | ID | Specialty | Bot |
|-------|----|-----------|-----|
| 🔒 שומר | `shomer` | Security, scanning, SSL, ports | @TeamShomer_Bot |
| ⚙️ קודר | `koder` | Code, bugs, deployment, API | @TeamKoder_Bot |
| 🎨 צייר | `tzayar` | Design, images, UI, logos | @TeamTzayar_Bot |
| 🔍 חוקר | `researcher` | Research, best practices | @TeamResearcher_Bot |
| 🧪 בודק | `bodek` | QA, testing, regression | @TeamBodek_Bot |
| 📊 דאטא | `data` | MongoDB, SQL, migrations | @TeamData_Bot |
| 🐛 דיבאגר | `debugger` | Error tracking, log analysis | @TeamDebugger_Bot |
| 🐳 דוקר | `docker` | Docker, containers, DevOps | @TeamDocker_Bot |
| 🖥️ פרונט | `front` | Frontend, HTML, CSS, JS | @TeamFront_Bot |
| ⚡ באק | `back` | Backend, API, Node.js | @TeamBack_Bot |
| 🧪 טסטר | `tester` | E2E, unit, integration tests | @TeamTester_Bot |
| ♻️ ריפקטור | `refactor` | Refactoring, optimization | @TeamRefactor_Bot |
| 📡 מוניטור | `monitor` | Monitoring, alerts, uptime | @TeamMonitor_Bot |
| 🚀 אופטימייזר | `optimizer` | Performance, caching | @TeamOptimizer_Bot |
| 🔗 אינטגרטור | `integrator` | APIs, webhooks, integrations | @TeamIntegrator_Bot |
| 🤖 עובד | `worker` | General tasks | @TeamTWorker_Bot |

---

## Learning System

SwarmClaw learns from every task:

```bash
# Agents learn before starting
swarm/inject-lessons.sh "task description"  # Returns relevant past lessons

# Agents record after completing
swarm/learn.sh lesson koder medium "Fixed CORS issue" "Always check nginx proxy_pass headers"
swarm/learn.sh score koder success
```

Lessons are stored in `learning/lessons.jsonl` and automatically injected into future task instructions.

---

## Setup Guide

### Prerequisites
- Node.js 18+
- OpenClaw agent platform
- Telegram Bot tokens (one per agent)
- Puppeteer dependencies (`apt install chromium-browser`)

### Installation

```bash
# 1. Clone the swarm directory
git clone <repo> && cd swarm

# 2. Configure bot tokens
echo "YOUR_BOT_TOKEN" > .koder-token
echo "YOUR_BOT_TOKEN" > .shomer-token
# ... for each agent

# 3. Configure OpenClaw hooks in openclaw.json
# hooks.enabled = true, hooks.token = "your-token"

# 4. Install cron
echo "* * * * * $(pwd)/dispatch-watcher.sh >> /tmp/dispatch-watcher.log 2>&1" | crontab -

# 5. Create required directories
mkdir -p /tmp/{agent-tasks,dispatch-queue,agent-done,spawn-request}
```

### OpenClaw Hook Configuration

```json
{
  "hooks": {
    "enabled": true,
    "token": "your-secret-token",
    "mappings": [{
      "match": { "path": "agent-watcher" },
      "action": "agent",
      "wakeMode": "now",
      "deliver": true,
      "allowUnsafeExternalContent": true
    }]
  }
}
```

---

## CLI Reference

### dispatch.sh — Full pipeline dispatch
```bash
swarm/runner/dispatch.sh <agent_id> "task" [options]

Options:
  --url URL           URL to verify after completion
  --test "command"    Test command to run for verification
  --project /path     Project directory
  --expect "text"     Text that must appear on the page
  --scroll-to "sel"   CSS selector to scroll to for screenshot
  --name "Topic Name" Custom topic name
```

### send.sh — Send as agent bot
```bash
swarm/send.sh <agent_id> <thread_id> "message" [--photo path]
```

### create-topic.sh — Create Telegram topic
```bash
THREAD=$(swarm/create-topic.sh "⚙️ Task Name" "" koder)
```

### spawn-agent.sh — Generate task text
```bash
TASK=$(swarm/spawn-agent.sh koder $THREAD "Fix the bug" "npm test" /root/Project)
```

### learn.sh — Learning system
```bash
swarm/learn.sh lesson <agent> <severity> "what" "lesson"
swarm/learn.sh score <agent> success|fail
swarm/learn.sh query "keywords"
```

### verify-and-report.js — Independent verification
```bash
node swarm/runner/verify-and-report.js <agent> <thread> \
    [--url URL] [--test "cmd"] [--project /path] [--expect "text"]
# Exit: 0=PASS, 1=FAIL/retry, 2=ESCALATE
```

### dispatch-watcher.sh — Automation daemon
```bash
# Runs via cron every minute. Handles:
# - New dispatches → spawn agents
# - Done markers → verify & report
# - Stuck agents → escalate
```

---

## File Structure

```
swarm/
├── runner/
│   ├── dispatch.sh              # Full pipeline dispatch
│   ├── agent-runner.js          # Agent execution engine
│   ├── verify-and-report.js     # Independent verification
│   └── screenshot-with-login.js # Authenticated screenshots
├── dispatch-watcher.sh          # Cron-based automation daemon
├── agent-watcher.sh             # Done-marker watcher
├── create-topic.sh              # Telegram topic creation
├── send.sh                      # Multi-bot message sending
├── spawn-agent.sh               # Task text generation
├── learn.sh                     # Learning system
├── inject-lessons.sh            # Lesson injection
├── learning/
│   ├── lessons.jsonl            # Accumulated lessons
│   └── scores.json              # Agent performance scores
├── agent-reports/               # Structured task reports
├── logs/                        # Message logs (JSONL)
└── memory/                      # Agent memory storage
```

---

## License

Proprietary — SwarmClaw by TeamWork
