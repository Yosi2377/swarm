# Swarm System Audit Report
**Date:** 2026-02-20
**Audited by:** Claude Code + Or (orchestrator)

## Summary
The swarm infrastructure is **mostly functional** — bots work, send.sh works, documentation is solid. The main problems are:
1. Claude Code keeps getting SIGKILL when writing files (needs investigation)
2. send.sh has several bugs
3. The orchestrator (Or) doesn't follow the rules consistently

## What Works ✅
- **All 7 bot tokens valid:** or, shomer, koder, tzayar, worker, researcher, bodek
- **send.sh:** Sends messages to Telegram, supports threads, photos, logging
- **Learning system:** 56 lessons accumulated, top lesson applied 32 times
- **Pipeline system:** Comprehensive (sandbox → verify → review → deploy → verify_prod → done)
- **Documentation:** Detailed ORCHESTRATOR.md (routing, delegation rules) and SYSTEM.md (agent behavior rules)
- **60+ shell scripts** for various automation tasks
- **Watchdog system** for monitoring stuck agents
- **24 test files** in tests/

## What's Broken ❌

### 1. Orchestrator Doesn't Follow Rules
- Works directly on production instead of sandbox
- Writes code itself instead of delegating to agents
- Doesn't create Telegram topics for tasks
- Doesn't use pipeline.sh flow

### 2. sessions_send Unreliable
- `sessions_send` to topic-based session keys often times out
- Agents don't always wake up when activated
- Sub-agents (sessions_spawn) work more reliably

### 3. Claude Code SIGKILL
- Claude Code gets killed by system when running longer tasks
- Happens specifically when trying to write files
- Not OOM (33GB free RAM), not in dmesg
- Possibly OpenClaw sandbox timeout or process limits

### 4. Agent Response Rate
- Agents sometimes don't respond after send.sh + sessions_send
- Watchdog should detect this but unclear if it's running

## Bugs in send.sh
1. **JSON injection:** Thread ID from user input inserted unescaped into JSON
2. **No token file check:** Missing token file → cryptic error instead of clear message
3. **jq crash on non-numeric thread:** `--argjson thread` expects number
4. **No caption length check:** Photo captions >1024 chars silently fail
5. **Mixed content-type:** JSON vs form-data thread handling inconsistency

## Recommendations (Priority Order)

### P0 — Fix Now
1. Fix send.sh bugs (input validation, token check)
2. Investigate Claude Code SIGKILL — check process limits, cgroups
3. Make orchestrator rules enforceable (not just documented)

### P1 — Fix Soon
4. Switch to Claude Code CLI for coding tasks (more reliable than sessions_spawn)
5. Add healthcheck that verifies all agents can receive and respond to messages
6. Create simple test: send task → verify agent responds within 60s

### P2 — Improve
7. Clean up 250 auto-generated skill files
8. Archive old task files
9. Add monitoring dashboard for agent activity
