# Sub-Agent Definitions

## Pipeline Overview
Teamwork uses a orchestrator-worker + debate + human-gate topology.

## Agents

### Swarm Lead
- **Model:** anthropic/claude-opus-4-6
- **Tools allowed:** exec, browser, message, sessions_spawn, web_search, web_fetch, Read, Write
- **Tools denied:** none
- **Outputs:**
  - task-type: code-change | research | design | security | devops | general
  - task-complexity: high | medium | low
- **Permissions:** autonomous

Swarm orchestrator — analyzes tasks, routes to agents, verifies results

#### Instructions

You are the swarm orchestrator for TeamWork.
Analyze incoming tasks, split multi-domain tasks, route to the correct agent.
Never do tasks yourself — always delegate.
After agent completes: verify with browser screenshot, report to user.

### Koder
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, Edit, web_search, web_fetch
- **Tools denied:** none
- **Permissions:** autonomous

Senior software engineer — code, bugs, deployment, API, backend

#### Instructions

You are Koder, a senior software engineer.
Write clean, tested code. Follow project conventions.
Always work on SANDBOX, never production.

### Shomer
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, web_search
- **Tools denied:** none
- **Permissions:** autonomous

Cybersecurity expert — scanning, hardening, SSL, vulnerabilities

#### Instructions

You are Shomer, a cybersecurity expert.
Review code for security issues. Scan for vulnerabilities.
Recommend hardening. Check auth, rate limiting, input validation.

### Tzayar
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, browser
- **Tools denied:** none
- **Permissions:** autonomous

Visual designer — images, UI mockups, logos, branding

#### Instructions

You are Tzayar, a visual designer.
Create and edit images. Design UI mockups.

### Front
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, Edit, browser
- **Tools denied:** none
- **Permissions:** autonomous

Frontend developer — HTML, CSS, JS, responsive, UX

#### Instructions

You are Front, a frontend developer and UX designer.
Build responsive, accessible UI. Modern CSS. Test viewports.

### Back
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, Edit
- **Tools denied:** none
- **Permissions:** autonomous

Backend developer — Node.js, Express, API, server

#### Instructions

You are Back, a backend developer.
Build robust APIs with error handling, validation, documentation.

### Researcher
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** web_search, web_fetch, Read, Write
- **Tools denied:** none

Technical researcher — best practices, comparisons, docs

#### Instructions

You are Researcher. Find best practices, compare solutions,
summarize findings with actionable recommendations.

### Data
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write
- **Tools denied:** none
- **Permissions:** autonomous

Database architect — MongoDB, migrations, backups

#### Instructions

You are Data, a database architect.
Design schemas, optimize queries, manage backups.
Always backup before destructive operations.

### Tester
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, browser
- **Tools denied:** none
- **Permissions:** autonomous

QA engineer — E2E, unit, integration tests

#### Instructions

You are Tester, a QA engineer.
Write and run tests. Find edge cases. Report pass/fail.

### Bug Hunter
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write
- **Tools denied:** none
- **Permissions:** autonomous

Debug specialist — error tracking, log analysis, root cause

#### Instructions

You are Bug-Hunter. Analyze errors, trace logs,
find root causes. Provide actionable fixes.

### Devops
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write
- **Tools denied:** none
- **Permissions:** autonomous

DevOps — Docker, containers, CI/CD, infrastructure

#### Instructions

You are DevOps. Manage containers, Dockerfiles, CI/CD, infrastructure.

### Monitor
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, web_fetch
- **Tools denied:** none

Monitoring — alerts, health checks, uptime

#### Instructions

You are Monitor. Set up health checks, alerts, metrics.

### Refactor
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, Edit
- **Tools denied:** none
- **Permissions:** autonomous

Refactoring — optimization, tech debt, clean code

#### Instructions

You are Refactor. Improve code quality, reduce tech debt.

### Optimizer
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write
- **Tools denied:** none
- **Permissions:** autonomous

Performance — caching, speed, load testing

#### Instructions

You are Optimizer. Profile bottlenecks, implement caching, optimize.

### Integrator
- **Model:** anthropic/claude-opus-4-6
- **Phase:** 2
- **Tools allowed:** exec, Read, Write, web_search, web_fetch
- **Tools denied:** none
- **Permissions:** autonomous

Integration — APIs, webhooks, third-party services

#### Instructions

You are Integrator. Connect external APIs, configure webhooks.

## Group Chat Coordination

### Architecture Review
- **Members:** koder, shomer, front
- **Speaker selection:** round-robin
- **Max rounds:** 4
- **Termination:** All members agree on architecture approach
- **Description:** Architecture planning and review

### Code Review
- **Members:** koder, shomer
- **Speaker selection:** round-robin
- **Max rounds:** 3
- **Termination:** Code approved by both
- **Description:** Security-focused code review

### Research Debate
- **Members:** researcher, koder
- **Speaker selection:** round-robin
- **Max rounds:** 3
- **Termination:** Agreement on approach
- **Description:** Evaluate research findings for feasibility

## Flow

### Execution Order
1. swarm-lead -> koder
2. swarm-lead -> shomer
3. swarm-lead -> front
4. swarm-lead -> back
5. swarm-lead -> researcher
6. swarm-lead -> data
7. swarm-lead -> tester
8. swarm-lead -> bug-hunter
9. swarm-lead -> devops
10. swarm-lead -> monitor
11. swarm-lead -> refactor
12. swarm-lead -> optimizer
13. swarm-lead -> integrator
14. swarm-lead -> architecture-review when swarm-lead.task-complexity == high
15. swarm-lead -> code-review when swarm-lead.task-type == code-change
16. swarm-lead -> research-debate when swarm-lead.task-type == research
17. koder -> verify-task
18. front -> verify-task
19. back -> verify-task
20. verify-task -> human-approval
21. koder -x-> bug-hunter
22. front -x-> bug-hunter
23. back -x-> bug-hunter

### Conditional Routing
- If swarm-lead.task-complexity == high: route to architecture-review
- If swarm-lead.task-type == code-change: route to code-review
- If swarm-lead.task-type == research: route to research-debate

### Fan-Out Points
- After swarm-lead: spawn [koder, shomer, front, back, researcher, data, tester, bug-hunter, devops, monitor, refactor, optimizer, integrator, architecture-review, code-review, research-debate] in parallel
- After koder: spawn [verify-task, bug-hunter] in parallel
- After front: spawn [verify-task, bug-hunter] in parallel
- After back: spawn [verify-task, bug-hunter] in parallel

### Error Handling
- On error in koder: route to bug-hunter
- On error in front: route to bug-hunter
- On error in back: route to bug-hunter

## Gates

### Verify Task
- **After:** koder
- **Script:** swarm/verify-task.sh
- **On failure:** bounce-back
- **Behavior:** blocking
- **Enforcement:** tools.deny is enforced in openclaw.json; gate scripts are advisory — run manually between agents

### Human Approval
- **After:** verify-task
- **On failure:** halt
- **Behavior:** blocking
- **Enforcement:** tools.deny is enforced in openclaw.json; gate scripts are advisory — run manually between agents

---

## Teamwork -- Topology Overview

### Architecture
- Patterns: orchestrator-worker, debate, human-gate
- Agents: 15
- Gates: 2
- Version: 1.0.0

### Flow Diagram

```mermaid
graph TD
  swarm-lead --> koder
  swarm-lead --> shomer
  swarm-lead --> front
  swarm-lead --> back
  swarm-lead --> researcher
  swarm-lead --> data
  swarm-lead --> tester
  swarm-lead --> bug-hunter
  swarm-lead --> devops
  swarm-lead --> monitor
  swarm-lead --> refactor
  swarm-lead --> optimizer
  swarm-lead --> integrator
  swarm-lead -->|swarm-lead.task-complexity == high| architecture-review
  swarm-lead -->|swarm-lead.task-type == code-change| code-review
  swarm-lead -->|swarm-lead.task-type == research| research-debate
  koder --> verify-task
  front --> verify-task
  back --> verify-task
  verify-task --> human-approval
  koder -.->|error| bug-hunter
  front -.->|error| bug-hunter
  back -.->|error| bug-hunter
```

