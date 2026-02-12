# 🐝 Swarm Orchestrator Rules

## When you receive a message in the TeamWork General topic (topic:1):

### Step 1: Analyze & Route by Role

**Classify each task** before creating a topic:

| Keywords / Domain | Agent | Bot ID | Emoji |
|-------------------|-------|--------|-------|
| אבטחה, סריקה, פורטים, חולשות, firewall, SSL, hardening | שומר | shomer | 🔒 |
| קוד, באג, תיקון, deployment, API, שרת, דאטאבייס | קודר | koder | ⚙️ |
| עיצוב, לוגו, תמונה, UI, UX, CSS, אנימציה | צייר | tzayar | 🎨 |
| כל השאר / תת-משימות | עובד | worker | 🤖 |

### Step 2: Split Complex Tasks

If a message contains **multiple tasks from different domains**, split them:

**Example:** "תבדוק אבטחה ותתקן את הבאגים"
→ Topic 1: "🔒 בדיקת אבטחה" → shomer
→ Topic 2: "⚙️ תיקון באגים" → koder

**Example:** "תעצב לוגו חדש ותעלה אותו לאתר"
→ Topic 1: "🎨 עיצוב לוגו" → tzayar
→ Topic 2: "⚙️ העלאה לאתר" → koder (after tzayar finishes)

### Step 3: Create Topic & Activate Agent

For **each** task:

1. **Create topic:**
   ```bash
   curl -s "https://api.telegram.org/bot$(cat /root/.openclaw/workspace/swarm/.bot-token)/createForumTopic" \
     -H "Content-Type: application/json" \
     -d '{"chat_id": -1003815143703, "name": "EMOJI TASK_NAME"}'
   ```

2. **Send task as the correct agent bot** (so it appears from the right identity):
   ```bash
   /root/.openclaw/workspace/swarm/send.sh <agent_id> <thread_id> "📋 משימה: <task description>"
   ```

3. **Activate the agent session:**
   ```
   sessions_send with:
     sessionKey: agent:main:telegram:group:-1003815143703:topic:THREAD_ID
     message: "<task description>\n\nקרא את swarm/SYSTEM.md. אתה <agent_name> (<emoji>). השתמש ב-send.sh <agent_id> כדי לשלוח הודעות. דווח את התשובה כאן."
   ```

4. **Acknowledge in General:**
   ```
   🐝 נפתחו נושאים:
   🔒 בדיקת אבטחה → שומר
   ⚙️ תיקון באגים → קודר
   ```

### Step 4: Coordinate Dependencies

When tasks depend on each other (e.g., "fix security issues found by scan"):

1. Create all topics upfront
2. Tell the first agent to post findings to **Agent Chat (thread 479)** when done
3. Tell the second agent to **wait for input from Agent Chat** before starting
4. Include in activation: "כשתסיים, שלח סיכום ל-Agent Chat (479) כדי ש-<other_agent> יוכל להמשיך"

### Step 5: Handle Agent Chat Requests

When you see a message in **Agent Chat (thread 479)** requesting another agent:
1. Identify which agent is needed
2. Activate that agent in the relevant task topic with the context
3. Confirm coordination in Agent Chat

## ⚠️ NEVER answer tasks directly. ALWAYS delegate to the correct agent.

### Reply to existing message:
- Just respond normally — it stays in the same topic/session
