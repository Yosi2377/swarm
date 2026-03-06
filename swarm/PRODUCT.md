# SwarmClaw — Multi-Agent Orchestration Platform

## Vision
מערכת סוכנים אוטונומית שעובדת על כל פרויקט, עם dashboard, Telegram integration, ו-API.
מוצר שאפשר למכור לחברות.

## מה הלקוח מקבל

### 1. Setup בדקה אחת
```bash
swarmclaw init my-project /path/to/code
# → יוצר config, מחבר ל-Telegram group, מגדיר agents
```

### 2. Telegram Group אוטומטי
- כל פרויקט = group עם topics
- כל משימה = topic נפרד
- סוכנים עם בוטים ייעודיים (koder, shomer, tester...)
- המשתמש כותב "תקן את הlogin" → המערכת עושה הכל

### 3. Dashboard (Web UI)
- **סוכנים** — מצב, היסטוריה, ציונים
- **משימות** — pipeline: todo → working → review → done
- **לוגים** — כל פעולה, כל commit, כל screenshot
- **ביצועים** — success rate, זמן ממוצע, עלות tokens
- **הגדרות** — הוספת פרויקטים, agents, rules

### 4. API
```
POST /api/tasks        — צור משימה
GET  /api/tasks/:id    — סטטוס + לוגים
GET  /api/agents       — רשימת סוכנים + מצב
GET  /api/dashboard    — סטטיסטיקות
POST /api/projects     — הוסף פרויקט
```

### 5. Agent Quality (מה שחסר היום)
- **Evaluator Agent** — סוכן נפרד שבודק עבודה של אחרים
- **E2E verification** — לא רק "יש commit" אלא בדיקה אמיתית מהדפדפן
- **Auto-retry with context** — כשנכשל, מקבל feedback מפורט ומנסה שוב
- **Project-agnostic** — עובד על כל stack, לא hardcoded ל-BotVerse

## ארכיטקטורה

```
┌─────────────────────────────────────────────┐
│                 SwarmClaw                     │
├──────────┬──────────┬───────────┬───────────┤
│ Dashboard│ API      │ Orchestr. │ Evaluator │
│ (React)  │ (Express)│ (Core)    │ (LLM)     │
├──────────┴──────────┴───────────┴───────────┤
│              OpenClaw (Engine)               │
├──────────┬──────────┬───────────────────────┤
│ Telegram │ sessions │ Tools (git, browser,  │
│ Bots     │ _spawn   │ exec, web_search)     │
└──────────┴──────────┴───────────────────────┘
```

## מה קיים (✅) ומה חסר (❌)

### ✅ יש כבר:
- OpenClaw engine + sessions_spawn
- Telegram bots (15 סוכנים)
- send.sh, create-topic.sh
- spawn-agent.sh, verify-task.sh
- Learning system (lessons, scores)
- Basic orchestrator logic

### ❌ חסר:
- [ ] **Project config system** — swarmclaw.yaml per project
- [ ] **Project-agnostic agents** — לא hardcoded URLs/ports
- [ ] **Evaluator agent** — LLM-based verification
- [ ] **Dashboard UI** — React web app
- [ ] **REST API** — Express server
- [ ] **CLI tool** — `swarmclaw init/status/task`
- [ ] **Multi-project support** — switch between projects
- [ ] **Onboarding flow** — new user setup
- [ ] **Documentation** — for customers
- [ ] **Billing/licensing** — for selling

## שלב 1 — Core (שבוע 1-2)

### 1.1 Project Config
```yaml
# swarmclaw.yaml
name: my-project
path: /root/MyProject
service: my-service          # systemd service name
stack: node                  # node/python/php/...
urls:
  production: https://mysite.com
  sandbox: http://localhost:9000
db: mongodb://localhost/mydb
test_cmd: "npm test"
agents:
  - koder
  - shomer
  - tester
```

### 1.2 Evaluator Agent
סוכן נפרד שמקבל:
- תיאור המשימה המקורית
- מה הסוכן עשה (commits, report)
- URL לבדוק
ומחזיר:
- PASS / FAIL + הסבר מפורט
- אם FAIL: בדיוק מה לתקן

### 1.3 Orchestrator Refactor
- קורא swarmclaw.yaml
- שולח project context לסוכנים (לא hardcoded)
- Evaluator בלולאה (עד 3 retries)

## שלב 2 — Dashboard + API (שבוע 3-4)
- Express API server
- React dashboard
- Real-time updates via WebSocket

## שלב 3 — Polish + Docs (שבוע 5)
- CLI tool
- Documentation
- Demo video
- Landing page

## מה מבדיל אותנו
1. **Telegram-native** — לא צריך IDE, עובד מהטלפון
2. **Multi-agent with personalities** — לא סתם "agent 1, agent 2"
3. **Built-in evaluation loop** — הסוכנים באמת בודקים את עצמם
4. **Works on any project** — config file + done
5. **Runs on OpenClaw** — open source engine
