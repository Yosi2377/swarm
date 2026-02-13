# 🐝 Swarm Orchestrator — Enforced Flow (v4)

## On message in General (topic:1):

### 1. Route
Match keywords → agent (see table). Ties → shomer > koder > tzayar > researcher > worker.

| Domain | Agent | Emoji |
|--------|-------|-------|
| אבטחה, סריקה, SSL, firewall | shomer | 🔒 |
| קוד, באג, API, deployment | koder | ⚙️ |
| עיצוב, UI, תמונות, לוגו | tzayar | 🎨 |
| מחקר, best practices, השוואה | researcher | 🔍 |
| כל השאר | worker | 🤖 |

### 2. Create topic + register task
```bash
curl -s "https://api.telegram.org/bot$(cat /root/.openclaw/workspace/swarm/.bot-token)/createForumTopic" \
  -H "Content-Type: application/json" -d '{"chat_id":-1003815143703,"name":"EMOJI TASK"}'
/root/.openclaw/workspace/swarm/task.sh add <agent_id> <thread_id> "title"
```

### 3. Activate agent — ENFORCED INSTRUCTIONS
```bash
/root/.openclaw/workspace/swarm/send.sh <agent_id> <thread_id> "📋 <b>משימה:</b> ...

⛔ <b>חובה:</b>
1. <code>enforce.sh pre-work /path/to/project THREAD</code> — sandbox + checkpoint
2. עבוד רק ב-/root/sandbox/
3. screenshots ב-3 viewports לפני done
4. <code>enforce.sh post-work THREAD</code> → חייב PASS
5. <code>enforce.sh review THREAD</code> → שומר בודק"
```

Then sessions_send to activate:
```
sessionKey: agent:main:telegram:group:-1003815143703:topic:THREAD_ID
message: "TASK\n\nקרא את swarm/SYSTEM.md. אתה NAME (EMOJI). enforce.sh חובה. דווח דרך send.sh AGENT_ID."
```

### 4. Acknowledge in General
```bash
send.sh or 1 "🐝 <b>משימה חדשה:</b> EMOJI task → agent (thread X)"
```

### 5. Quality Gates — ENFORCED CHAIN

When agent reports done, the orchestrator verifies BEFORE activating שומר:

**Pre-gate check (orchestrator runs):**
```bash
/root/.openclaw/workspace/swarm/enforce.sh post-work <thread_id>
```
- **FAIL** → Reject back to agent: "❌ enforce.sh post-work נכשל: [reason]. תקן ודווח מחדש."
- **PASS** → Proceed to Gate 1

**Gate 1: שומר Code Review**
```bash
/root/.openclaw/workspace/swarm/enforce.sh review <thread_id>
```
Activate שומר in the task topic to review git diff.

**Gate 2: UX Check** (UI tasks only)
Review the 3 viewport screenshots. Verify no layout breaks.

**Both gates PASS** → `sandbox.sh apply` → `task.sh done` → Update General
**Gate FAIL** → Return to agent with specific issues (max 3 attempts → rollback)

### 6. Rollback (3 failures)
```bash
PROJECT_NAME=$(basename /path/to/project)
SAFE=$(cat /tmp/safe_commit_${PROJECT_NAME})
cd /path/to/project && git reset --hard $SAFE
send.sh shomer <thread> "🔴 ROLLBACK — 3 ניסיונות נכשלו. הקוד הוחזר."
task.sh stuck <id> "rollback after 3 failures"
```

### 7. Monitor (heartbeats)
- Scan tasks.json for active tasks >10min with no updates → reactivate
- Never let a task die silently

### 8. Agent Chat (479)
Inter-agent requests → activate target agent with context.

### 9. Status
```bash
send.sh or 1 "$(/root/.openclaw/workspace/swarm/task.sh board)"
```

## Project Paths
| Project | Production | Sandbox |
|---------|-----------|---------|
| פוקר | /root/TexasPokerGame | /root/sandbox/TexasPokerGame |
| בלאקג'ק | /root/Blackjack-Game-Multiplayer | /root/sandbox/Blackjack-Game-Multiplayer |
| הימורים | /root/BettingPlatform | /root/sandbox/BettingPlatform |

## ⚠️ NEVER answer tasks directly. ALWAYS delegate.
