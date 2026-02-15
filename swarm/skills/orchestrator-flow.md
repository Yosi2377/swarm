# Skill: Orchestrator Flow (אור)

## Golden Rules
1. ⛔ NEVER code directly — ALWAYS delegate to agents
2. ⛔ NEVER skip topics — every task gets its own topic
3. ⛔ NEVER push to production without user approval

## Task Flow
```
User Request
    ↓
1. Create Telegram Topic (emoji + name)
2. Create Task File: swarm/tasks/<topic-id>.md
3. Post task summary in topic
4. Activate Agent Session:
   - sessionKey: agent:main:telegram:group:-1003815143703:topic:<TOPIC_ID>
   - message: "קרא את swarm/tasks/<id>.md + swarm/skills/<skill>.md. אתה <name> (<emoji>). עבוד ב-sandbox. שלח screenshots כשתסיים."
5. Report to General: "🐝 נפתח נושא #<id>, הועבר ל<agent>"
    ↓
Agent Works (in sandbox)
    ↓
Agent Posts Screenshots
    ↓
6. Activate שומר for Code Review
    ↓
שומר Posts Review
    ↓
7. Report to User: "מוכן לבדיקה + screenshots"
    ↓
User Approves
    ↓
8. Deploy to Production (rsync + restart)
9. Close Topic
```

## Agent Routing
| Domain | Agent | Send As |
|--------|-------|---------|
| קוד, באגים, API, UI | קודר ⚙️ | koder |
| אבטחה, review | שומר 🔒 | shomer |
| עיצוב, תמונות | צייר 🎨 | tzayar |
| מחקר | חוקר 🔍 | researcher |
| כל השאר | עובד 🤖 | worker |

## Activating an Agent
```bash
# 1. Send task to topic as the agent's bot
/root/.openclaw/workspace/swarm/send.sh <agent_id> <thread_id> "📋 משימה: ..."

# 2. Activate agent session
sessions_send:
  sessionKey: agent:main:telegram:group:-1003815143703:topic:<THREAD_ID>
  message: "קרא את swarm/tasks/<id>.md + swarm/skills/<skill>.md. ..."
```

## Creating Task File
```bash
cat > /root/.openclaw/workspace/swarm/tasks/<topic-id>.md << 'EOF'
# Task: ...
(use task-template.md format)
EOF
```
