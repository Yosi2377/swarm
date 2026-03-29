# OpenClaw fork for Yossi — required behavior changes

## Goal
Make OpenClaw behave as a continuity-first, verify-before-answer assistant for Yossi's workflow, without rewriting the whole platform.

## Problem statement
Current failures are not mainly about tool availability. They are about runtime behavior:
- answers before retrieval
- answers before verification
- weak previous-conversation recall in topic/thread workflows
- poor source selection under ambiguity
- speculative completion claims in operational tasks

## Design principle
Do not rely on the model to "remember to do the right thing".
Enforce the right flow in the product/runtime.

---

## 1. Continuity-first retrieval pipeline

### Required behavior
Before answering any stateful prompt, OpenClaw should build a working context pack automatically.

### Trigger classes
Auto-trigger retrieval on prompts matching one or more of:
- previous conversation / what did we talk about / last message / what did you send
- service state / is it running / why is it down / open it / start it
- follow-up references: "this", "that", "same topic", "previous", "last one"
- reply-context present on inbound message
- topic/thread session messages

### Retrieval order
1. reply context (if present)
2. current session history window
3. topic/thread-specific session artifacts
4. memory search
5. other logs only as fallback

### Hard rule
Do not answer previous-conversation questions from generic memory first.
Use session-local artifacts first.

### Needed implementation areas
- inbound metadata normalization
- session history fetch path
- reply-context extraction / prioritization
- runtime prompt assembly / context pack creation

---

## 2. Verify-before-answer discipline

### Required behavior
For operational claims, no success statement before live verification.

### Examples
- "server is up" -> only after real probe
- "tool opened" -> only after process/UI verification
- "fixed" -> only after test/HTTP/UI validation
- "last message was ..." -> only after retrieval

### Hard rules
- no speculative success claims
- no guessed previous-message answers
- no guessed service identity/port/path
- no static file serving from workspace root

### Needed implementation areas
- task classifier for operational prompts
- verification policy layer
- response gating before final user-visible answer

---

## 3. Source selection policy

### Problem
Model chose wrong source repeatedly (old swarm logs instead of reply/session context).

### Required behavior
Rank sources by relevance for the question type.

### Example mapping
- previous-message question -> reply context / session history
- service-down question -> process/HTTP probe/system state
- "open this tool" -> installed command/docs/local project files
- prior decision / preference -> memory_search + memory_get

### Hard rule
Wrong-source answers should be harder than saying "checking source of truth".

---

## 4. Yossi mode runtime profile

### Mode name
`continuity_strict` (working name)

### Behavior
- retrieval first
- verification first
- concise user-facing replies
- no filler apologies loops
- no generic restatement unless requested
- operational bias over conversational bias

### Output pattern for stateful tasks
Internal flow:
1. classify request
2. select source-of-truth
3. fetch/verify
4. answer with result only

### User-visible style
- short
- concrete
- no analysis dump unless asked

---

## 5. Topic/thread memory support

### Required behavior
Topic-based chats should automatically preserve and reload a compact rolling state.

### Needed data
- last confirmed task state
- last confirmed assistant action
- last verified service/tool state
- unresolved blockers
- last reply anchor

### Suggested implementation
For each session/topic maintain a compact state snapshot, updated after each completed turn.

Possible file key ideas:
- by session key
- by channel+chat+topic

---

## 6. Safety hardening from observed failures

### Must prevent
- serving `/root/.openclaw/workspace` via ad-hoc static server
- opening ports without knowing what is exposed
- claiming success before checking endpoint content
- replacing source-of-truth with old unrelated logs

### Required guardrails
- workspace-root static server denylist
- "public bind" warning or hard block for unsafe roots
- endpoint content verification helpers
- stronger destructive/unsafe operation review

---

## 7. Codex-specific harnessing

### Problem
Codex inside OpenClaw currently needs more behavioral scaffolding.

### Required runtime scaffolding
- inject explicit retrieval plan for continuity prompts
- inject explicit verification checklist for ops prompts
- require source citation internally before answering state questions
- bias toward tools over speculation

### Goal
Reduce model variance by forcing structure in stateful/ops interactions.

---

## 8. MVP implementation order

### Phase 1 — must-have
1. automatic previous-conversation retrieval policy
2. reply-context prioritization
3. verify-before-answer gating for service/tool claims
4. unsafe static-server guardrail
5. continuity_strict runtime mode

### Phase 2
6. rolling session/topic state snapshot
7. source-selection policy per task type
8. Codex prompt harness improvements

### Phase 3
9. topic-aware subagent/retrieval routing
10. UI/debug surfaces for why a source was chosen

---

## Definition of done for MVP
OpenClaw fork is considered meaningfully fixed for Yossi when it can reliably:
- answer "what did we talk about" from actual session/topic context
- answer "what was the last message" from source-of-truth context
- refuse to claim a service/tool is working until verified
- avoid exposing unsafe local directories
- behave consistently in Telegram topic workflows without acting like every day is the first day
