# Agent Definitions — Architecture Decision
**Created:** 2026-02-13
**Agent:** 🤖 עובד (based on multi-agent research)

## Decision
Enhanced agent definitions in agents.json v4 based on research of CrewAI, AutoGen, MetaGPT, ChatDev, and LangGraph.

## Changes Made
1. **Added `description`** — one-line English description for each agent (used for auto-routing)
2. **Added `backstory`** — Hebrew personality/context (improves agent behavior quality)
3. **Added `constraints`** — explicit boundaries per agent (what NOT to do)
4. **Added `keywords`** — Hebrew + English keywords for auto-routing
5. **Enhanced settings** — autoRouting, feedbackLoopMaxRetries, sharedMemoryPath

## Agent Count: 5 (Sweet Spot)
Research confirmed 3-5 agents is optimal. Our 5 agents + orchestrator is ideal:
- אור (orchestrator) — routes, doesn't work
- שומר (security + QA) — reviews all code
- קודר (development) — writes code
- צייר (design) — visual assets
- חוקר (research) — analysis + reports
- עובד (general) — everything else

## Key Insight
Quality of role definitions > number of agents. The backstory and constraints improvements should yield better agent behavior.

## References
- CrewAI: role/goal/backstory pattern
- AutoGen: description for routing
- MetaGPT: SOP-based coordination
- Research task: swarm/memory/task-1368.md
