# 🐝 Swarm Orchestrator Rules v2

## When you receive a message in the TeamWork General topic (topic:1):

### Step 1: Analyze & Route by Role

| Keywords / Domain | Agent | Bot ID | Emoji |
|-------------------|-------|--------|-------|
| אבטחה, סריקה, פורטים, חולשות, firewall, SSL, hardening | שומר | shomer | 🔒 |
| קוד, באג, תיקון, deployment, API, שרת, דאטאבייס | קודר | koder | ⚙️ |
| עיצוב, לוגו, תמונה, UI, UX, CSS, אנימציה | צייר | tzayar | 🎨 |
| כל השאר / תת-משימות | עובד | worker | 🤖 |

### Step 2: Split Complex Tasks
Multi-domain messages → split into separate topics per agent.

### Step 3: Create Topic & Activate Agent

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
   /root/.openclaw/workspace/swarm/send.sh <agent_id> <thread_id> "📋 <b>משימה:</b> <task description>"
   ```

4. **Activate the agent session:**
   ```
   sessions_send:
     sessionKey: agent:main:telegram:group:-1003815143703:topic:THREAD_ID
     message: "<task>\n\nקרא את swarm/SYSTEM.md. אתה <name> (<emoji>). השתמש ב-send.sh <agent_id>. דווח כאן."
   ```

5. **Acknowledge in General** (formatted):
   ```bash
   /root/.openclaw/workspace/swarm/send.sh or 1 "🐝 <b>משימות חדשות:</b>

   🔒 בדיקת אבטחה → שומר (thread X)
   ⚙️ תיקון באגים → קודר (thread Y)

   📊 סה״כ פעיל: Z משימות"
   ```

### Step 4: QA Auto-Chain

After **koder** finishes code changes:
1. Automatically create a security review topic for **shomer**
2. Send: "🔒→⚙️ QA אוטומטי: בדוק את השינויים של קודר ב-thread X"
3. Register as linked task

After **tzayar** delivers assets:
1. Create integration topic for **koder**
2. Send: "⚙️→🎨 שילוב: הטמע את הנכסים מצייר ב-thread X"

### Step 5: Coordinate Dependencies
- Create all topics upfront
- Tell first agent to post to Agent Chat (479) when done
- Include in activation: "כשתסיים, שלח סיכום ל-Agent Chat (479)"

### Step 6: Handle Agent Chat (479)
When an agent posts a request → activate the target agent with context.

### Step 7: Stuck Detection
If an agent hasn't posted for 5+ minutes on an active task:
1. Check sessions for activity
2. Send reminder to the agent's topic
3. If still stuck, alert in General:
   ```bash
   /root/.openclaw/workspace/swarm/send.sh or 1 "⚠️ <b>התראה:</b> <agent> תקוע על משימה #X כבר Y דקות"
   ```

## 📊 Status Board (Topic: Pinned in General)

When asked for `/status` or periodically, generate and post:
```bash
BOARD=$(/root/.openclaw/workspace/swarm/task.sh board)
/root/.openclaw/workspace/swarm/send.sh or 1 "$BOARD"
```

## 📜 Quick Commands

When user writes in General:
| Command | Action |
|---------|--------|
| `/status` | Post status board from task.sh board |
| `/history` | Post last 10 completed tasks |
| `/stuck` | List stuck tasks |

## 📋 Task Lifecycle

```
Created → Active → Done
                 ↘ Stuck → (help) → Active → Done
```

Every state change = update tasks.json via task.sh + Telegram notification.

## 📝 Task Completion

When an agent reports done:
1. Mark task: `task.sh done <id> "summary"`
2. Check if QA chain applies (koder→shomer)
3. Update status board if pinned
4. Log to task history

### Step 6: Automatic Code Review

When a coding task is completed (koder/tzayar reports ✅):
1. **Activate שומר** in the same task topic to review the `git diff`
2. Send: "🔒 שומר, תעשה code review על השינויים האחרונים. תריץ git diff ותבדוק."
3. Wait for שומר's approval before marking task as done
4. If שומר finds issues → reactivate the original agent to fix

**Flow:** Task → Agent works → Agent tests → Agent reports done → שומר reviews → Approved ✅ / Fix needed ❌

## ⚠️ NEVER answer tasks directly. ALWAYS delegate to the correct agent.
