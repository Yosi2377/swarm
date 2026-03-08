# 🐝 Swarm — Execution Reliability Layer for AI Agents

> "The agents are replaceable. The reliability layer is the product."

## What is Swarm?

Swarm is an **execution reliability layer** that ensures AI agents actually complete tasks correctly. Instead of trusting agents when they say "done", Swarm independently verifies their work using typed contracts, semantic verification, and smart retry.

## Architecture

```
Task → Contract → Agent → Verification → Pass/Retry/Escalate
```

### Core Modules (swarm/core/)

| Module | Purpose |
|--------|---------|
| **task-contract.js** | Define typed contracts with acceptance criteria |
| **contract-templates.js** | Pre-built templates per task type (9 types) |
| **contract-validator.js** | Validate contracts before execution |
| **state-machine.js** | Strict lifecycle: queued → running → verifying → pass/fail |
| **task-runner.js** | Orchestrate task execution with state tracking |
| **failure-taxonomy.js** | Classify failures into 9 categories |
| **smart-retry.js** | Context-aware retry with failure-specific prompts |
| **semantic-verify.js** | 10+ criterion types (HTTP, file, DB, browser, custom) |
| **orchestrator-bridge.js** | Glue connecting all modules |
| **auto-retry-runner.js** | Automatic retry without human intervention |
| **task-decomposer.js** | Break large tasks into subtasks |
| **fast-prompt.js** | Lean prompts for faster agent execution |
| **agent-consultation.js** | Inter-agent communication with auto-routing |
| **project-ports.js** | Project configuration (ports, URLs, paths) |

### Key Features

- **Task Contracts** — Every task has typed acceptance criteria, not free text
- **9 Task Types** — code_fix, feature, ui_change, api_endpoint, db_migration, security_fix, refactor, research, config_change
- **Semantic Verification** — Checks HTTP status, file contents, DB counts, service health, screenshots
- **Smart Retry** — Different strategy per failure type (auth=escalate, build=retry with error, partial=finish remaining)
- **Auto-Routing** — Security questions → Shomer, design → Tzayar, etc.
- **Task Decomposition** — Breaks "do X and Y and Z" into independent subtasks
- **Speed Optimization** — Simple tasks get lean prompts, complex tasks get full context

## Quick Start

```bash
# Dispatch a task with contract
TASK=$(bash swarm/dispatch-task.sh koder 1234 "Fix login button" "/root/BotVerse")

# Verify after agent completes
bash swarm/verify-task.sh koder 1234
# exit 0 = pass, exit 1 = retry, exit 2 = escalate

# Full auto-verification with screenshots
bash swarm/auto-verify-and-report.sh koder 1234 "https://botverse.dev" "Fix login"

# Start dashboard
bash swarm/api/start-dashboard.sh
# → http://95.111.247.22:9200
```

## API

```
GET  /api/health          — System health
GET  /api/tasks           — List all tasks
GET  /api/tasks/:id       — Task details + contract
GET  /api/agents          — Agent list with scores
GET  /api/stats           — Pass rate, active tasks, avg time
POST /api/tasks           — Create new task with auto-contract
POST /api/tasks/:id/retry — Manual retry
```

## Tests

```bash
# Run all tests (157+)
node swarm/tests/test-contract.js          # 41 tests
node swarm/core/tests/test-state-machine.js # 21 tests
node swarm/core/tests/test-failure-taxonomy.js # 30 tests
node swarm/core/tests/test-semantic-verify.js  # 28 tests
node swarm/core/tests/test-integration.js      # 19 tests
node swarm/core/tests/test-auto-retry.js       # 4 tests
node swarm/core/tests/test-decomposer.js       # 7 tests
node swarm/core/tests/test-fast-prompt.js      # 7 tests
node swarm/api/test-api.js                     # 5 tests
```

## Agent Communication

Agents communicate via Telegram topics. Inter-agent help requests are auto-routed:
- Security → 🔒 שומר (Shomer)
- Code → ⚙️ קודר (Koder)
- Design → 🎨 צייר (Tzayar)
- Research → 🔍 חוקר (Researcher)
- QA → 🧪 בודק (Bodek)

## License

Proprietary — © 2026
