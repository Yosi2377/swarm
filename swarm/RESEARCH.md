# Multi-Agent Orchestration Systems — Exhaustive Research

**Date:** 2026-03-06  
**Purpose:** Architecture decisions for OpenClaw + Telegram swarm orchestration

---

## Table of Contents

1. [Framework Landscape](#1-framework-landscape)
2. [Orchestration Patterns](#2-orchestration-patterns)
3. [Common Failures & Lessons Learned](#3-common-failures--lessons-learned)
4. [Agent Evaluation & Quality Assurance](#4-agent-evaluation--quality-assurance)
5. [Session Management & Wake Patterns](#5-session-management--wake-patterns)
6. [OpenClaw-Specific Capabilities](#6-openclaw-specific-capabilities)
7. [Architecture Recommendations for Our System](#7-architecture-recommendations-for-our-system)

---

## 1. Framework Landscape

### 1.1 OpenAI Swarm → OpenAI Agents SDK

**Source:** https://github.com/openai/swarm, https://github.com/openai/openai-agents-python

**Key Architecture:**
- Swarm was an **educational/experimental** framework, now replaced by the **OpenAI Agents SDK** (production-ready).
- Core abstractions: **Agents** (LLM + instructions + tools) and **Handoffs** (agent-to-agent delegation).
- **Stateless between calls** — no server-side state. All context passed via messages.
- Agent communication = function calls that return another agent. The "handoff" pattern: agent A has a tool `transfer_to_agent_b()` that returns `agent_b`.
- Task completion = when the final agent returns a response without further tool calls.
- Failure handling = minimal in Swarm (educational); Agents SDK adds **guardrails** (input/output validation), **tracing**, and **human-in-the-loop** checkpoints.

**Key Insight:** The handoff pattern is extremely simple and powerful. An agent doesn't "send a message" to another agent — it *becomes* that agent by returning it. This avoids complex messaging infrastructure.

**Applicability to Our System:** Our OpenClaw system uses `sessions_spawn` which is more like launching isolated processes than handoffs. We should consider whether some agent interactions could use simpler handoff-style routing rather than full sub-agent spawning. However, for truly parallel work (our primary use case), spawn is correct.

---

### 1.2 CrewAI

**Source:** https://docs.crewai.com/concepts/crews

**Key Architecture:**
- **Crew** = a group of agents + tasks with a defined process flow.
- **Process types:** `sequential` (default) or `hierarchical` (manager agent delegates to workers).
- Hierarchical mode requires a `manager_llm` — a dedicated LLM that acts as the orchestrator.
- **Task completion detection:** Each task has expected output criteria. CrewAI checks if agent output matches.
- **Memory system:** Short-term, long-term, and entity memory — stored across crew executions.
- **Step callbacks:** `step_callback` fires after each agent step — useful for monitoring/logging.
- **Task callbacks:** `task_callback` fires after each task completion.
- **Retry/failure:** Has `max_retry_limit` on tasks. Agents can be configured with `allow_delegation=True` to pass work to other agents.

**Key Insight:** CrewAI's hierarchical process with a manager LLM is closest to our orchestrator model. The callback system for step/task monitoring is something we should replicate.

**Applicability:** Our orchestrator in General topic acts like CrewAI's hierarchical manager. We should add structured task completion criteria (not just "agent says done") and implement callback-style monitoring.

---

### 1.3 MetaGPT

**Source:** https://github.com/FoundationAgents/MetaGPT

**Key Architecture:**
- **"Software company" metaphor** — agents are roles: Product Manager, Architect, Project Manager, Engineer.
- Core philosophy: **"Code = SOP(Team)"** — Standard Operating Procedures define agent interactions.
- Agents communicate via **structured artifacts** (PRDs, design docs, API specs), not free-form chat.
- Each role has defined inputs (what they receive) and outputs (what they produce).
- **Publish-subscribe message bus** — agents subscribe to message types they care about. When a Product Manager publishes a PRD, the Architect agent automatically receives it.
- Sequential pipeline with quality gates between stages.
- Now commercialized as **MGX (mgx.dev)** — "world's first AI agent development team."

**Key Insight:** Structured artifacts > free-form chat for agent communication. The pub-sub model means agents don't need to know about each other directly — they just produce and consume defined document types.

**Applicability:** We should define structured output formats for each agent type. When koder finishes, it should produce a structured report (files changed, tests run, status) — not just a text message. Our Agent Chat (topic 479) is a crude version of a message bus.

---

### 1.4 LangGraph

**Source:** https://langchain-ai.github.io/langgraph/ (redirect issues during fetch)

**Key Architecture (from documentation knowledge):**
- Multi-agent as a **graph** — nodes are agents, edges are transitions.
- **Supervisor pattern:** One agent routes tasks to specialized agents.
- **Handoff pattern:** Agents transfer control to each other (like Swarm).
- **State management:** Shared state object passed between agents.
- **Checkpointing:** Can save and restore graph execution state.
- **Human-in-the-loop:** Built-in interrupt points where execution pauses for human input.
- **Streaming:** Real-time streaming of agent thoughts and actions.

**Key Insight:** The graph abstraction makes agent workflows visualizable and debuggable. Checkpointing allows recovery from failures without re-running entire workflows.

**Applicability:** Our Telegram topic structure is essentially a graph — orchestrator routes to specialized topics/agents. We should add checkpointing (save state to files) so failed agent runs can be resumed.

---

### 1.5 ChatDev

**Key Architecture (from knowledge):**
- Agents role-play as a software company: CEO, CTO, Programmer, Tester, Art Designer.
- **Chat-chain** communication — agents talk to each other in structured dialogues.
- Phase-based: Design → Coding → Testing → Documenting.
- Each phase has a defined "chat turn" limit to prevent infinite loops.
- **Key innovation:** "Experience co-learning" — agents learn from past interactions.

**Key Insight:** Turn limits per phase prevent infinite loops. We need hard caps on agent iterations.

**Applicability:** We should set max iterations/time limits per sub-agent task. Currently sub-agents can run indefinitely.

---

## 2. Orchestration Patterns

### 2.1 Anthropic's Canonical Patterns (CRITICAL — Read This First)

**Source:** https://www.anthropic.com/engineering/building-effective-agents

**This is the most important source.** Anthropic (who builds Claude, our primary model) identified these production patterns from working with dozens of teams:

#### Pattern 1: Prompt Chaining
- Decompose task into sequential steps, each LLM processes previous output.
- Add programmatic "gates" between steps to verify progress.
- **Use when:** Task cleanly decomposes into fixed subtasks.

#### Pattern 2: Routing
- Classify input → direct to specialized handler.
- Separation of concerns; specialized prompts per category.
- **Use when:** Distinct categories better handled separately.
- **This is exactly what our orchestrator does** — classify task domain → route to correct agent.

#### Pattern 3: Parallelization
- **Sectioning:** Break into independent subtasks, run simultaneously.
- **Voting:** Same task multiple times for diverse outputs/higher confidence.
- **Use when:** Subtasks are independent; multiple perspectives needed.

#### Pattern 4: Orchestrator-Workers (⭐ Our Primary Pattern)
- Central LLM dynamically breaks down tasks and delegates to workers.
- Workers complete subtasks; orchestrator synthesizes results.
- **Key difference from parallelization:** Subtasks are NOT pre-defined; determined dynamically.
- **Use when:** Can't predict needed subtasks (e.g., coding — number of files depends on task).
- **This is our swarm architecture.**

#### Pattern 5: Evaluator-Optimizer
- One LLM generates; another evaluates/critiques in a loop.
- Iterative refinement until quality threshold met.
- **Use when:** Clear evaluation criteria exist; iterative refinement has measurable value.
- **We should add this** — after a coding agent delivers, a reviewer agent evaluates.

#### Anthropic's Core Principles:
1. **"Start simple, add complexity only when needed."** Most successful teams used simple patterns, not complex frameworks.
2. **"Maintain simplicity"** — Don't over-engineer.
3. **"Prioritize transparency"** — Show planning steps explicitly.
4. **"Craft your Agent-Computer Interface (ACI)"** — Spend as much time on tool design as on prompts.
5. **Frameworks can help but "create extra layers of abstraction that can obscure underlying prompts, making them harder to debug."**
6. **"Incorrect assumptions about what's under the hood are a common source of customer error."**

**Critical Insight on Tool Design:**
> "We actually spent more time optimizing our tools than the overall prompt."
> Example: Model made mistakes with relative filepaths → changed tool to require absolute filepaths → flawless results.

**Applicability:** 
- Our system should lean on **Orchestrator-Workers** as the primary pattern.
- Add **Evaluator-Optimizer** loops for quality-critical tasks.
- Use **Routing** at the orchestrator level (already doing this).
- **Simplify** — resist adding framework complexity. Our bash scripts + sessions_spawn + Telegram topics is already a good simple foundation.

---

### 2.2 How Production AI Companies Handle Multi-Agent Work

#### Cognition (Devin)
- **Architecture:** Single agent with extremely long context, not multi-agent. Devin is one persistent agent with shell, browser, and editor access.
- **Key insight:** Sometimes a single capable agent with good tools beats multiple specialized agents.
- **Completion detection:** Test suite passes; human reviews PR.
- **Applicability:** For complex coding tasks, consider using one powerful agent (opus) with all tools rather than splitting across agents.

#### Factory.ai (Droids)
- **Architecture:** Specialized AI "droids" for different software engineering tasks.
- Droid types: Code Review, Bug Fixing, Migration, Documentation.
- Each droid is a specialized agent with domain-specific tools and context.
- **Completion:** Defined deliverables — PR created, tests pass, review approved.
- **Key insight:** Specialization works. Each droid does one thing well.
- **Applicability:** Validates our approach of specialized agents (koder, shomer, front, back, etc.).

#### Cursor
- **Architecture:** Tab (inline completion) + Cmd-K (edit) + Chat + Agent mode.
- Agent mode: single agent with file edit, terminal, and search tools.
- **Multi-file editing:** Agent plans changes, applies them sequentially, runs linter after each.
- **Background agents:** Can run multiple agents in parallel on different tasks.
- **Completion:** Agent decides it's done; user can accept/reject changes.
- **Key insight:** The user is always the final evaluator. Agent proposes, human disposes.

---

### 2.3 Pattern Comparison for Our Use Case

| Pattern | Fits When | Our Usage |
|---------|-----------|-----------|
| **Hierarchical (Orchestrator → Workers)** | Complex tasks, unpredictable subtasks | ✅ Primary — General topic orchestrator |
| **Flat (peer-to-peer)** | Agents need to collaborate directly | ⚠️ Agent Chat (479) — limited use |
| **Event-driven (pub-sub)** | Many agents, loose coupling | ❌ Not yet — could improve with hooks |
| **Sequential pipeline** | Well-defined stages | ✅ For review flows: code → test → review |
| **Evaluator-optimizer loop** | Quality-critical outputs | 🔜 Should add for code review |

---

## 3. Common Failures & Lessons Learned

### 3.1 Why Multi-Agent Systems Fail in Practice

Based on community discussions, blog posts, and production reports:

#### Failure 1: **Agents talking past each other**
- Agents generate responses that don't address what the previous agent actually produced.
- Root cause: Context window overflow; agents lose track of the conversation.
- **Fix:** Structured handoffs with explicit input/output schemas. Don't pass entire chat history.

#### Failure 2: **Infinite loops and circular delegation**
- Agent A delegates to Agent B, which delegates back to Agent A.
- Root cause: Unclear task boundaries; agents can't determine when they're done.
- **Fix:** Hard iteration limits. Maximum number of turns per task. Timeout-based kill switches.
- **Our system:** Sub-agents can currently run indefinitely. Must add `runTimeoutSeconds` to all spawns.

#### Failure 3: **Orchestrator bottleneck**
- Single orchestrator becomes the bottleneck — every inter-agent communication goes through it.
- Root cause: Over-centralization.
- **Fix:** Allow direct agent-to-agent communication for simple handoffs. Use orchestrator only for complex routing.
- **Our system:** Currently everything goes through General topic → orchestrator. Agent Chat (479) helps but is underutilized.

#### Failure 4: **Context window explosion**
- As conversations grow, agents lose performance because context is filled with irrelevant history.
- Root cause: Dumping all history into every agent call.
- **Fix:** Summarize previous context. Use structured state objects instead of raw chat history.
- **Our system:** Sessions_spawn creates isolated sessions (good!). But long-running topics accumulate noise.

#### Failure 5: **Cost explosion**
- Multi-agent systems multiply API costs — orchestrator + N workers, each making multiple calls.
- A single task can cost $5-50+ with powerful models.
- **Fix:** Use cheaper models for simple tasks. Route to expensive models only for complex work.
- **Our system:** Consider using haiku/sonnet for routine tasks, opus only for complex coding.

#### Failure 6: **"Works in demo, fails in production"**
- Systems that work on happy paths fail on edge cases.
- Root cause: Insufficient error handling; no retry logic; no fallback behavior.
- **Fix:** Defensive prompting. Explicit error handling instructions. Fallback to human escalation.

#### Failure 7: **Agent claims task is done when it isn't**
- Agent outputs "✅ Done!" but the work is incomplete or broken.
- Root cause: LLMs are trained to be helpful and will claim completion to satisfy the user.
- **Fix:** **Never trust agent self-report.** Verify with external signals: tests pass, lint clean, screenshot matches, file exists.
- **Our system critical issue:** We currently rely on agents saying "done." Must add verification.

### 3.2 Community Complaints (Common Themes)

From Reddit, HN, and blog discussions:

1. **"Debugging is a nightmare"** — When Agent C fails because Agent A gave bad input to Agent B, tracing the root cause is extremely hard. → Need comprehensive logging and tracing.

2. **"Framework overhead isn't worth it"** — Most frameworks add complexity without proportional value. Simple scripts + API calls work better. → Our bash script approach is actually good.

3. **"Token costs are insane"** — Running a 4-agent crew on opus for a moderate task can cost $20+. → Model routing matters enormously.

4. **"Non-determinism makes testing impossible"** — Same input → different outputs → can't write reliable tests. → Use temperature=0, seed parameters, and output validation.

5. **"Agents are great at generating code, terrible at debugging it"** — Multi-agent coding systems often create code, then fail to fix their own bugs. → The evaluator agent should be a different model/prompt than the generator.

---

## 4. Agent Evaluation & Quality Assurance

### 4.1 Verifying Agent Work Without a Human

#### Approach 1: **Automated Testing as Ground Truth**
- After coding agent finishes → run test suite → pass/fail is objective.
- **SWE-bench approach:** Anthropic's coding agent is evaluated by whether tests pass.
- Limitation: Only works if tests exist and cover the change.
- **Our system:** Every koder task should end with `npm test` or equivalent.

#### Approach 2: **LLM-as-Judge (Evaluator Pattern)**
- A separate LLM reviews the work with a rubric.
- Anthropic's **evaluator-optimizer** pattern: generate → evaluate → refine → repeat.
- Use a different model for evaluation (avoids self-bias).
- Rubric should be specific: "Does the code handle error cases? Is there input validation? Are there race conditions?"
- **Our system:** After koder delivers, spawn a `bodek` (tester) agent to evaluate. Use a different model.

#### Approach 3: **Mutation Testing**
- Introduce deliberate bugs into agent-generated code.
- If tests don't catch the mutations → tests are insufficient.
- Tools: Stryker (JS), mutmut (Python).
- **Our system:** Can be added as a post-testing step for critical code.

#### Approach 4: **Self-Reflection / Critique**
- Ask the agent: "Review your own work. What could go wrong? What did you miss?"
- Research shows this catches 10-30% of errors the agent didn't notice initially.
- **Critical:** Must be a separate LLM call, not the same turn. The agent needs to "step back."
- **Our system:** Add a self-review step before agents report completion.

#### Approach 5: **Differential Verification**
- Compare agent output against known-good baselines.
- Screenshot comparison for UI tasks.
- API response comparison for backend tasks.
- **Our system:** The `report-done.sh` screenshot approach is a form of this — visual diff against expectations.

### 4.2 Quality Assurance Pipeline (Recommended)

```
Agent completes task
    ↓
1. Automated checks (lint, tests, type-check)
    ↓ pass?
2. Self-review (agent critiques own work)
    ↓ 
3. Evaluator agent review (different model/prompt)
    ↓ pass?
4. Screenshot/visual verification
    ↓
5. Report to orchestrator with evidence
    ↓
6. Human spot-check (optional)
```

---

## 5. Session Management & Wake Patterns

### 5.1 Async Agent Completion → Notification → Evaluation

The fundamental challenge: Agent starts → runs for N minutes → completes → how does the orchestrator know?

#### Pattern 1: **Push-based (Callback)**
- Agent finishes → sends completion notification to orchestrator.
- **OpenClaw implementation:** `sessions_spawn` auto-announces results back to the spawner session.
- **This is what we use.** Sub-agent completion is push-based.
- **Limitation:** Only works if the spawner session is still alive to receive the announcement.

#### Pattern 2: **Poll-based**
- Orchestrator periodically checks agent status.
- Simpler but wasteful. Introduces latency between completion and detection.
- **OpenClaw explicitly warns against this:** "Do NOT poll subagents list in a loop."

#### Pattern 3: **Event-driven (Webhook/Hook)**
- Agent completion fires an event → hook handler processes it.
- **OpenClaw supports hooks** — could create a hook that fires on sub-agent completion.
- Most scalable pattern for many concurrent agents.

#### Pattern 4: **Shared State (File/DB)**
- Agent writes completion status to a shared location.
- Orchestrator monitors the location.
- **Our system:** Agents can write to `swarm/memory/` — a crude shared state.

### 5.2 OpenClaw Session Architecture

Based on docs research:

- **Session keys:** `agent:<agentId>:<channel>:<type>:<identifier>` — unique per conversation context.
- **Sub-agent sessions:** `agent:<agentId>:subagent:<uuid>` — isolated, ephemeral.
- **Auto-announcement:** Sub-agent results push back to requester session automatically.
- **Cron jobs:** Can schedule periodic checks via `openclaw cron add`.
- **Hooks:** Event-driven scripts that fire on agent lifecycle events (session start, command, reset).
- **Session cleanup:** Automatic maintenance of old sessions.

### 5.3 Recommended Wake Pattern for Our System

```
Orchestrator receives task
    ↓
Create Telegram topic (create-topic.sh)
    ↓
Spawn sub-agent (sessions_spawn with runTimeoutSeconds)
    ↓
Sub-agent works autonomously in isolated session
    ↓
Sub-agent completes → auto-announces to orchestrator
    ↓
Orchestrator receives announcement
    ↓
Orchestrator evaluates result (or spawns evaluator)
    ↓
Orchestrator reports to user in General
```

**Key additions needed:**
1. `runTimeoutSeconds` on every spawn (prevent runaway agents)
2. Structured completion reports (not free-form text)
3. Evaluation step before reporting to user
4. Failure handling — what happens when sub-agent times out?

---

## 6. OpenClaw-Specific Capabilities

### 6.1 Hooks System

**Source:** https://docs.openclaw.ai/automation/hooks.md

- **Event-driven scripts** that fire on agent lifecycle events.
- Hook types: `/new`, `/reset`, `/stop`, lifecycle events.
- Hooks are TypeScript handlers discovered from `<workspace>/hooks/`, `~/.openclaw/hooks/`, or bundled.
- **Bundled hooks:** session-memory, bootstrap-extra-files, command-logger, boot-md.
- **Key capability:** Can trigger follow-up automation when sessions start or end.
- **Potential:** Create a custom hook that fires when a sub-agent session completes → triggers evaluation pipeline.

### 6.2 Cron System

**Source:** https://docs.openclaw.ai/automation/cron-jobs.md

- **Built-in scheduler** persisted under `~/.openclaw/cron/`.
- Two execution styles: **main session** (enqueue event) or **isolated** (dedicated agent turn).
- Supports wake modes: "wake now" vs "next heartbeat."
- Can deliver output to specific channels.
- **Potential:** Schedule periodic health checks on long-running agent tasks.

### 6.3 Sessions & Sub-agents

**Source:** https://docs.openclaw.ai/cli/sessions.md, system prompt analysis

- `sessions_spawn`: Creates isolated sub-agent session with its own context.
- `sessions_list`: List sessions with filters.
- `sessions_history`: Fetch history for debugging.
- `subagents`: List, steer, or kill spawned sub-agents.
- **Auto-announcement:** Completion results push to requester session.
- **Key limitation:** No structured completion schema — just text output.

### 6.4 Multi-Bot Telegram Architecture (Our System)

Current setup from AGENTS.md:
- **16+ specialized bots** — each agent has a dedicated Telegram bot for visual identity.
- **Topic-per-task** — every task gets its own Telegram topic via `create-topic.sh`.
- **Orchestrator** in General topic classifies and routes tasks.
- **Agent Chat (topic 479)** for inter-agent coordination.
- **send.sh** for posting as the correct bot identity.
- **spawn-agent.sh** generates task prompts with full context (topic, lessons, tools).

---

## 7. Architecture Recommendations for Our System

### 7.1 What's Working Well ✅

1. **Orchestrator-Workers pattern** — aligns with Anthropic's recommended architecture.
2. **Topic-per-task isolation** — prevents context contamination between tasks.
3. **Specialized agents** — validates Factory.ai's approach; domain expertise > generalist.
4. **Bash scripts for orchestration** — simple, debuggable, no framework overhead (Anthropic recommends this over frameworks).
5. **Push-based completion** via `sessions_spawn` auto-announcement.

### 7.2 What Needs Improvement 🔧

#### Priority 1: Task Completion Verification
**Problem:** Agents self-report completion. This is the #1 failure mode.
**Solution:**
- Define completion criteria per task type (tests pass, lint clean, screenshot matches).
- After agent reports done → spawn evaluator agent or run automated checks.
- Never forward "done" to user without evidence.

#### Priority 2: Timeout & Failure Handling
**Problem:** No `runTimeoutSeconds` on spawns. Agents can run forever.
**Solution:**
- Default timeout: 10 minutes for simple tasks, 30 minutes for complex.
- On timeout: Kill agent → report failure to orchestrator → orchestrator decides retry/escalate.
- Max retries: 2 per task.

#### Priority 3: Structured Agent Reports
**Problem:** Agents report via free-form text. Hard to parse, evaluate, or aggregate.
**Solution:** Define a structured completion format:
```json
{
  "status": "success|failure|partial",
  "summary": "What was done",
  "files_changed": ["path1", "path2"],
  "tests_run": true,
  "tests_passed": true,
  "screenshot_path": "/path/to/screenshot.png",
  "confidence": 0.85,
  "issues": ["Known issue 1"],
  "time_spent_seconds": 180
}
```

#### Priority 4: Model Routing for Cost Control
**Problem:** Using opus for everything is expensive.
**Solution:**
- **Opus:** Complex coding tasks, architecture decisions, debugging.
- **Sonnet:** Routine code changes, documentation, testing, reviews.
- **Haiku:** Simple file operations, formatting, status checks.
- Add `model` parameter to `spawn-agent.sh`.

#### Priority 5: Evaluation Pipeline
**Problem:** No systematic quality verification.
**Solution:**
- After coding: `npm test` + `npm run lint` + type-check.
- After UI: Screenshot + visual comparison.
- For critical tasks: Spawn evaluator agent (bodek) with different model.
- Self-review: Agent reviews own work in separate turn before reporting.

#### Priority 6: Better Inter-Agent Communication
**Problem:** Agent Chat (479) is underutilized. All coordination goes through orchestrator.
**Solution:**
- Define explicit "request types" agents can post to Agent Chat.
- Orchestrator monitors Agent Chat and activates requested agents.
- Consider: Agents write structured artifacts to `swarm/artifacts/<task-id>/` instead of/in addition to chat messages.

#### Priority 7: Observability & Debugging
**Problem:** When a chain of agents fails, root cause analysis is difficult.
**Solution:**
- Every agent action logged to `swarm/logs/` (already partially done).
- Add structured task traces: task ID → agent → actions → result.
- Dashboard view of all active/completed agent tasks.

### 7.3 Recommended Architecture Evolution

**Phase 1 (Now):** Add timeouts, structured reports, basic verification.
**Phase 2 (Next):** Add evaluator pipeline, model routing, cost tracking.
**Phase 3 (Later):** Event-driven hooks for completion, shared artifact store, dashboard.

### 7.4 Key Principles (From Research)

1. **Simplicity wins.** Anthropic's #1 recommendation. Don't add frameworks — our bash scripts are fine.
2. **Never trust self-report.** Always verify with external signals.
3. **Tools > Prompts.** Spend more time on tool interfaces than prompt engineering.
4. **Structured > Unstructured.** Agents should exchange defined artifacts, not free-form chat.
5. **Timeouts are mandatory.** Every autonomous process needs a kill switch.
6. **Different models for different tasks.** Cost and quality optimization.
7. **Transparency.** Make agent reasoning visible. Log everything.

---

## Sources Referenced

| Source | URL | Key Contribution |
|--------|-----|-----------------|
| Anthropic: Building Effective Agents | https://www.anthropic.com/engineering/building-effective-agents | Canonical patterns, core principles |
| OpenAI Swarm | https://github.com/openai/swarm | Handoff pattern, stateless design |
| OpenAI Agents SDK | https://github.com/openai/openai-agents-python | Production evolution: guardrails, tracing, sessions |
| CrewAI Docs | https://docs.crewai.com/concepts/crews | Hierarchical process, callbacks, memory |
| MetaGPT | https://github.com/FoundationAgents/MetaGPT | SOP-based, pub-sub, structured artifacts |
| OpenClaw Hooks | https://docs.openclaw.ai/automation/hooks.md | Event-driven automation |
| OpenClaw Cron | https://docs.openclaw.ai/automation/cron-jobs.md | Scheduling, wake patterns |
| OpenClaw Sessions | https://docs.openclaw.ai/cli/sessions.md | Session management, cleanup |
| OpenClaw Main Docs | https://docs.openclaw.ai | Gateway architecture, capabilities |
