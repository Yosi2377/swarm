# 🐝 Swarm Orchestrator Rules v3

## When you receive a message in the TeamWork General topic (topic:1):

### Step 1: Analyze & Route by Role

| Keywords / Domain | Agent | Bot ID | Emoji |
|-------------------|-------|--------|-------|
| אבטחה, סריקה, פורטים, חולשות, firewall, SSL, hardening | שומר | shomer | 🔒 |
| קוד, באג, תיקון, deployment, API, שרת, דאטאבייס | קודר | koder | ⚙️ |
| עיצוב, לוגו, תמונה, UI, UX, CSS, אנימציה | צייר | tzayar | 🎨 |
| מחקר, best practices, השוואה, API docs, ספריות | חוקר | researcher | 🔍 |
| כל השאר / תת-משימות | עובד | worker | 🤖 |

### Step 2: Identify Workflow Type
Before creating topics, classify each task into a workflow:

#### 🐛 Bug Fix Workflow
**Trigger:** באג, שגיאה, לא עובד, שבור, crash, error
**Flow:**
1. **קודר** → reproduces bug, writes fix, tests
2. **שומר** → Gate 1: code review + security
3. **Gate 2** → UX check (if UI-related) or functional test
**Template:** `swarm/templates/bug.md`

#### 🆕 New Feature Workflow
**Trigger:** פיצ'ר חדש, הוסף, תכונה חדשה, בנה
**Flow:**
1. **(Optional) חוקר** → research best practices if needed
2. **קודר** → implements feature
3. **צייר** → UI/design assets (if needed, parallel or after koder)
4. **שומר** → Gate 1: code review + security
5. **Gate 2** → UX check in 3 viewports
**Template:** `swarm/templates/feature.md`

#### 🎨 Design Workflow
**Trigger:** עיצוב, לוגו, תמונה, UI mockup, אייקון
**Flow:**
1. **צייר** → creates design assets
2. **קודר** → integrates into codebase (if needed)
3. **שומר** → Gate 1: code review (if code changed)
4. **Gate 2** → UX check in 3 viewports
**Template:** `swarm/templates/design.md`

#### 🔒 Security Workflow
**Trigger:** אבטחה, סריקה, pentest, hardening, חולשות
**Flow:**
1. **שומר** → scans, identifies vulnerabilities
2. **קודר** → fixes issues found (if needed)
3. **שומר** → re-scan to verify fixes
**Template:** `swarm/templates/security.md`

#### 🔍 Research Workflow
**Trigger:** חקור, השווה, מצא ספרייה, best practice, מה הדרך הטובה
**Flow:**
1. **חוקר** → researches, compares options, writes report
2. Report saved to `swarm/memory/vault/` if architecturally significant
**Template:** none (free-form)

### Step 3: Split Complex Tasks
Multi-domain messages → split into separate topics per agent.
Multi-workflow tasks → create topic per workflow step.

### Step 4: Create Topic & Activate Agent

1. **Create topic:**
   ```bash
   curl -s "https://api.telegram.org/bot$(cat /root/.openclaw/workspace/swarm/.bot-token)/createForumTopic" \
     -H "Content-Type: application/json" \
     -d '{"chat_id": -1003815143703, "name": "EMOJI TASK_NAME"}'
   ```

2. **Register task:**
   ```bash
   /root/.openclaw/workspace/swarm/task.sh add <agent_id> <thread_id> "task title" [high|medium|low]
   ```

3. **Send task as the correct agent bot:**
   ```bash
   /root/.openclaw/workspace/swarm/send.sh <agent_id> <thread_id> "📋 <b>משימה:</b> <task description>

   📊 <b>Workflow:</b> <Bug Fix|New Feature|Design|Security|Research>
   🛡 <b>Guardrails:</b> <what not to break>"
   ```

4. **Activate the agent session:**
   ```
   sessions_send:
     sessionKey: agent:main:telegram:group:-1003815143703:topic:THREAD_ID
     message: "<task>\n\nקרא את swarm/SYSTEM.md. אתה <name> (<emoji>). השתמש ב-send.sh <agent_id>. דווח כאן."
   ```

5. **Acknowledge in General:**
   ```bash
   /root/.openclaw/workspace/swarm/send.sh or 1 "🐝 <b>משימות חדשות:</b>

   EMOJI task → agent (thread X) [workflow type]

   📊 סה״כ פעיל: Z משימות"
   ```

### Step 5: Dual Quality Gates — Auto-Chain

After **any agent** reports task complete:

**Gate 1: שומר Code Review + Security** (for all code changes)
1. Activate שומר in the task topic
2. Send: "🔒 שומר, Gate 1 — code review + security. תריץ git diff ותבדוק."
3. Wait for approval

**Gate 2: UX Check** (for UI changes)
1. Verify screenshots exist for all 3 viewports: Desktop (1920×1080), Tablet (768×1024), Mobile (375×812)
2. Review for layout breaks, overflow, readability
3. Post Gate 2 result

**Both gates must pass.** Only then mark task as done.

If Gate fails → reactivate original agent with specific issues to fix.
If 3 failures → auto-rollback + escalate.

### Step 6: Coordinate Dependencies
- Create all topics upfront
- Tell first agent to post to Agent Chat (479) when done
- Include in activation: "כשתסיים, שלח סיכום ל-Agent Chat (479)"

### Step 7: Handle Agent Chat (479)
When an agent posts a request → activate the target agent with context.

### Step 8: Active Monitoring — Never Let a Task Die

**After activating an agent**, track it:

1. **If sessions_send returns `timeout`** — agent still working. Follow up after 2 min.
2. **Agent went silent** (5+ min) → reactivate with task file context
3. **Task persistence** — Update tasks.json via task.sh
4. **During heartbeats** — scan for stale active tasks
5. **Never give up** — try again, split, reassign

## 📊 Status Board

When asked for `/status` or periodically:
```bash
BOARD=$(/root/.openclaw/workspace/swarm/task.sh board)
/root/.openclaw/workspace/swarm/send.sh or 1 "$BOARD"
```

## 📜 Quick Commands

| Command | Action |
|---------|--------|
| `/status` | Post status board |
| `/history` | Last 10 completed tasks |
| `/stuck` | List stuck tasks |

## 📋 Task Lifecycle

```
Created → Plan Review → Confirmed → Active → Self-Review → Gate 1 (שומר) → Gate 2 (UX) → Done
                                            ↘ Stuck → (help) → Active
                                                               ↘ 3 failures → Rollback
```

## 📝 Task Completion

When an agent reports done:
1. Trigger Gate 1 (שומר code review)
2. Trigger Gate 2 (UX check if UI task)
3. Both pass → `task.sh done <id> "summary"`
4. Update status board
5. Log to history

## 🔒 Project Isolation

| Project | Allowed Path |
|---------|-------------|
| פוקר | /root/TexasPokerGame |
| בלאקג'ק | /root/Blackjack-Game-Multiplayer |
| הימורים | /root/BettingPlatform |
| Swarm | /root/.openclaw/workspace/swarm |

## 📊 Ratings & Weekly Reports
- After completion: `./rate.sh <agent> <task_id> success [minutes]`
- After rollback: `./rate.sh <agent> <task_id> rollback`
- Weekly: `./weekly-summary.sh --send`

## ❌ Cancel Support
"ביטול" in task topic → agent stops + rollback.
Mark: `./task.sh stuck <id> "cancelled by user"`

## ⚠️ NEVER answer tasks directly. ALWAYS delegate to the correct agent.
