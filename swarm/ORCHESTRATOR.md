# 🐝 Swarm Orchestrator — Pipeline Flow

## טבלת Routing

| Domain | Agent | Emoji |
|--------|-------|-------|
| אבטחה, סריקה, SSL, firewall | shomer | 🔒 |
| קוד, באג, API, deployment | koder | ⚙️ |
| עיצוב, UI, תמונות, לוגו | tzayar | 🎨 |
| מחקר, best practices, השוואה | researcher | 🔍 |
| בדיקות, QA, טסטים, regression | bodek | 🧪 |
| דאטא, MongoDB, SQL, migrations, backups | data | 📊 |
| דיבאג, errors, logs, profiling | debugger | 🐛 |
| Docker, containers, K8s, DevOps | docker | 🐳 |
| Frontend, HTML, CSS, JS, responsive | front | 🖥️ |
| Backend, API, Node.js, Express, server | back | ⚡ |
| E2E tests, unit tests, integration tests | tester | 🧪 |
| Refactoring, optimization, tech debt | refactor | ♻️ |
| Monitoring, alerts, health checks, uptime | monitor | 📡 |
| Performance, speed, caching | optimizer | 🚀 |
| APIs, webhooks, third-party integrations | integrator | 🔗 |
| כל השאר | worker | 🤖 |

Ties → shomer > koder > tzayar > researcher > bodek > worker

## Project Paths

| Project | Production | Sandbox |
|---------|-----------|---------|
| פוקר | /root/TexasPokerGame | /root/sandbox/TexasPokerGame |
| בלאקג'ק | /root/Blackjack-Game-Multiplayer | /root/sandbox/Blackjack-Game-Multiplayer |
| הימורים | /root/BettingPlatform | /root/sandbox/BettingPlatform |

---

## Flow A — הודעה חדשה מיוסי עד השלמה

### שלב 1: Route + פתיחת Topic
```bash
# 1. זהה סוכן מתאים לפי טבלת routing
# 2. פתח topic בטלגרם
RESULT=$(curl -s "https://api.telegram.org/bot$(cat swarm/.bot-token)/createForumTopic" \
  -H "Content-Type: application/json" \
  -d '{"chat_id":-1003815143703,"name":"EMOJI תיאור קצר"}')
THREAD=$(echo "$RESULT" | jq -r '.result.message_thread_id')
```

### שלב 2: Pipeline init
```bash
TASK_ID="task-${THREAD}"
swarm/pipeline.sh init "$TASK_ID" "$THREAD" "<agent_id>"
```

### שלב 3: שליחת משימה לסוכן
```bash
swarm/send.sh <agent_id> "$THREAD" "📋 <b>משימה:</b> תיאור מפורט

⛔ Pipeline חובה:
1. עבוד ב-sandbox בלבד
2. סיימת? → <code>swarm/pipeline.sh done-step $TASK_ID</code>
3. תקוע 5+ דק? → <code>swarm/ask-help.sh <agent> <target> $THREAD \"desc\"</code>
4. אסור deploy ישיר!"
```

### שלב 4: הפעלת סוכן
```bash
sessions_spawn(
  task="המשימה...\n\nקרא swarm/SYSTEM.md. אתה NAME (EMOJI). דווח דרך send.sh AGENT_ID.\nTask ID: TASK_ID\nThread: THREAD",
  label="task-THREAD"
)
```

### שלב 5: Watchdog ברקע
```bash
# הפעל פעם אחת — מנטר את כל המשימות
pgrep -f watchdog.sh || nohup swarm/watchdog.sh > /dev/null 2>&1 &
```

### שלב 6: דיווח ב-General
```bash
swarm/send.sh or 1 "🐝 <b>משימה חדשה:</b> EMOJI תיאור → agent (thread $THREAD)"
```

---

## Flow B — סוכן מדווח סיום

### שלב 1: Advance ל-verify_sandbox
```bash
swarm/pipeline.sh advance "$TASK_ID"
# current_step: sandbox(done) → verify_sandbox(active)
```

### שלב 2: הרצת verify
```bash
swarm/pipeline.sh verify "$TASK_ID" "http://localhost:PORT"
# מריץ verify/verify-frontend.sh או verify-backend.sh
# PASS → step marked done
# FAIL → חזרה לסוכן עם feedback
```

### שלב 3: Advance ל-review
```bash
swarm/pipeline.sh advance "$TASK_ID"
# current_step: verify_sandbox(done) → review(active)
```

### שלב 4: שליחת review ליוסי
```bash
# צלם screenshot
node -e "..." # puppeteer screenshot → /tmp/verify-THREAD.png

# שלח ליוסי ב-General עם screenshot + diff
swarm/send.sh or 1 "🔍 <b>Review מוכן</b>
📋 משימה: $TASK_ID
🤖 סוכן: AGENT
📸 screenshot מצורף
לאישור: pipeline.sh approve $TASK_ID
לדחייה: pipeline.sh reject $TASK_ID \"reason\"" --photo /tmp/verify-$THREAD.png
```

### שלב 5: יוסי מאשר → Deploy
```bash
swarm/pipeline.sh approve "$TASK_ID"
swarm/pipeline.sh advance "$TASK_ID"
# current_step: review(done) → deploy(active)

# Deploy
deploy.sh <project> --approved

swarm/pipeline.sh done-step "$TASK_ID"
swarm/pipeline.sh advance "$TASK_ID"
# current_step: deploy(done) → verify_prod(active)
```

### שלב 6: Verify production
```bash
swarm/pipeline.sh verify "$TASK_ID" "http://PRODUCTION_URL"
# PASS → done-step already marked
swarm/pipeline.sh advance "$TASK_ID"
# current_step: verify_prod(done) → done

swarm/send.sh or 1 "✅ <b>הושלם:</b> $TASK_ID — deployed + verified"
```

### שלב 5b: יוסי דוחה
```bash
swarm/pipeline.sh reject "$TASK_ID" "reason"
# חוזר ל-sandbox, סוכן מקבל הודעה אוטומטית
# חזור ל-Flow B מההתחלה כשהסוכן מסיים שוב
```

---

## Watchdog — ניטור רקע

רץ ברקע, בודק כל 2 דקות את כל המשימות הפעילות.

| זמן תקוע | פעולה |
|-----------|-------|
| 5 דק | ping — שולח תזכורת לסוכן |
| 10 דק | restart — מפעיל מחדש את הסוכן |
| 3 restarts | escalate — מדווח ליוסי ב-General |

Watchdog כותב לתור `/tmp/delegate-queue/`:
- `<agent>-ping.json` → שלח ping: `swarm/send.sh <agent> <thread> "עדיין עובד? דווח סטטוס"`
- `<agent>-restart.json` → הפעל מחדש: `sessions_spawn(...)` + `swarm/send.sh <agent> <thread> "🔄 restart — המשך מאיפה שעצרת"`
- `escalate-<task>.json` → `swarm/send.sh or 1 "⚠️ משימה $TASK_ID תקועה — 3 restarts, דרוש התערבות"`

---

## בקשות עזרה

כשסוכן תקוע ומבקש עזרה דרך `ask-help.sh`:

```bash
# הסוכן מריץ:
swarm/ask-help.sh <from-agent> <to-agent> <thread-id> "description"
# → נשלח ל-Agent Chat (479) + נוצר /tmp/delegate-queue/<to>-help.json
```

**Orchestrator מטפל:**
1. קרא את `/tmp/delegate-queue/<to>-help.json`
2. הפעל סוכן עוזר עם הקונטקסט
3. עדכן ב-Agent Chat (479)

---

## Agent Chat (Topic 479)

תיאום בין סוכנים. מעקב אחרי בקשות עזרה, dependency chains, ועדכוני סטטוס.

---

## 🐺 Ralph Loop — Koder Tasks

For coding tasks, use Ralph Loop instead of raw sessions_spawn.
Ralph provides: **planning phase → iterative building → auto-testing → notifications**.

### Setup & Run
```bash
# 1. Setup workspace
swarm/setup-ralph-task.sh "task-5400" "/root/sandbox/BettingPlatform" "Fix spreads" "Description..."

# 2. Edit AGENTS.md in the project with:
#    - Key files list
#    - test_command: <how to verify>
#    - VERIFY_URL: <url to screenshot>

# 3. Run the loop
swarm/ralph-koder.sh "task-5400" 5400 "/root/sandbox/BettingPlatform" 10
```

### How it works
1. **PLANNING** — Agent reads specs, creates IMPLEMENTATION_PLAN.md with numbered tasks
2. **BUILDING** — Each iteration: implement ONE task → test → commit → next
3. **Testing** — Auto-runs test_command after each change. Fails → retry
4. **Notifications** — Agent writes to `.ralph/pending-notification.txt`, OpenClaw picks up via cron:
   - `DONE` → task complete, notify orchestrator
   - `ERROR` → tests failing, may need help
   - `BLOCKED` → needs human decision
   - `DECISION` → architectural choice needed
5. **Clean sessions** — Each iteration is fresh context, memory lives in files

### Why this is better
- Agent can't say "fixed!" without tests passing
- Planning prevents jumping into wrong solution
- Each iteration is small and auditable (git commits)
- Orchestrator gets notified automatically on completion/errors
- No more 3 failed attempts with "done" reports

### When to use Ralph
- ✅ Any coding task (koder)
- ✅ Multi-step changes across files
- ✅ Bug fixes that need verification
- ❌ Quick one-line fixes (overkill)
- ❌ Non-coding tasks (research, design)

---

## כללי ברזל

1. **אור לא כותב קוד** — רק מתזמר
2. **אין deploy בלי אישור יוסי** — pipeline enforce
3. **כל עבודה ב-sandbox קודם** — אין חריגים
4. **screenshots חובה** — לפני כל review
5. **משימה אחת לסוכן** — פצל multi-domain למשימות נפרדות
6. **דיווח ב-General** — כל שלב משמעותי
7. **Watchdog תמיד רץ** — `pgrep -f watchdog.sh || nohup swarm/watchdog.sh &`
8. **screenshot אוטומטי** — ברגע שסוכן מסיים: בדוק → צלם → שלח screenshot + סיכום → אז דווח. לעולם לא לדווח בלי screenshot!
9. **learn.sh חובה** — כל task שמסתיים → learn.sh lesson + learn.sh score
10. **פיצול מקבילי** — כל מה שאפשר לפצל בלי חפיפת קבצים → sessions_spawn במקביל
11. **הזרקת לקחים** — לפני שליחת task, הרץ `learn.sh query "keywords"` וצרף לקחים רלוונטיים ישירות בהוראות ה-task. הסוכנים לא מריצים query בעצמם!

## עבודה מקבילית

כשיש כמה משימות — הפעל כמה סוכנים במקביל:
```bash
sessions_spawn(task="...", label="task-101")  # returns immediately
sessions_spawn(task="...", label="task-102")  # returns immediately
```
`sessions_spawn` = מקבילי (תמיד לעבודה). `sessions_send` = סדרתי (רק לפינגים קצרים).
