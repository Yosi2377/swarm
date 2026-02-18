# 🎯 Roadmap — Level 5 Agent System

## Phase 1: Foundation (שבוע 1) — רמה 4
Priority: מונע התנגשויות + סוכנים עצמאיים יותר

### 1.1 Git Branch Per Task ⏱️ 2h
- כל task פותח branch: `task-{id}-{agent}`
- סוכן עובד על branch שלו — אין התנגשויות
- merge רק אחרי evaluator + approval
- Scripts: `branch-task.sh`, `merge-task.sh`

### 1.2 Self-Healing Agents ⏱️ 1d
- סוכן נכשל → retry אוטומטי (עד 3 פעמים)
- בכל retry — קורא את השגיאה + לקחים רלוונטיים
- fallback: אם 3 retries נכשלו → מבקש עזרה מסוכן אחר
- שינויים: SYSTEM.md + wrapper script

### 1.3 Agent-to-Agent Communication ⏱️ 1d
- Delegation queue: `/tmp/delegate-queue/*.json`
- סוכן א' צריך עזרה → כותב request → סוכן ב' מקבל
- לא עובר דרך אור — ישיר
- Supervisor מנטר את ה-queue

### 1.4 Semantic Lesson Search ⏱️ 0.5d
- Replace keyword search with embeddings (Gemini/OpenAI)
- learn.sh query → vector similarity search
- Top 5 relevant lessons injected into task

---

## Phase 2: CI/CD (שבוע 2) — רמה 4.5
Priority: אוטומציה מלאה של deploy

### 2.1 Auto Test Generation ⏱️ 2d
- כל שינוי בקובץ → סוכן bodek כותב browser tests אוטומטית
- Tests נשמרים ב-`swarm/tests/{task-id}.json`
- Evaluator מריץ אותם אוטומטית

### 2.2 PR-style Workflow ⏱️ 1d
- branch → tests pass → PR message ב-General עם diff + screenshots
- Yossi approves → auto merge + deploy
- Yossi rejects → סוכן מקבל feedback ומתקן

### 2.3 Rollback System ⏱️ 0.5d
- כל deploy שומר snapshot מלא (git tag + DB dump)
- `rollback.sh {tag}` → חוזר לגרסה קודמת תוך 30 שניות
- Auto-rollback אם uptime check נכשל אחרי deploy

---

## Phase 3: Intelligence (שבוע 3) — רמה 5
Priority: סוכנים חכמים באמת

### 3.1 Full Autonomy Mode ⏱️ 2d
- סוכן מקבל task → מתכנן → מפצל → מבצע → בודק → מדווח
- לא צריך אור באמצע — רק בהתחלה ובסוף
- Orchestrator רק מנטר ומתערב אם תקוע

### 3.2 Multi-Project Awareness ⏱️ 1d
- Skills per project: betting, blackjack, poker, dashboard
- סוכן יודע לעבור בין פרויקטים
- Shared knowledge base across projects

### 3.3 Proactive Issue Detection ⏱️ 1d
- סוכנים סורקים קוד ומוצאים בעיות בעצמם
- "מצאתי bug פוטנציאלי ב-X" → פותח task אוטומטי
- Code quality monitoring (complexity, duplication)

### 3.4 Performance Learning ⏱️ 1d
- מודד זמן per task type
- לומד אילו tasks לוקחים יותר זמן ולמה
- Auto-adjusts timeouts ו-retry strategy
- Weekly intelligence report

---

## Metrics — איך נדע שהגענו

| Metric | רמה 3 (עכשיו) | רמה 4 | רמה 5 |
|--------|---------------|-------|-------|
| Tasks/day | 5-10 ידני | 15-20 חצי-אוטו | 30+ אוטונומי |
| Yossi interventions | 10+/day | 3-5/day | 0-2/day |
| Time to fix bug | 30-60 min | 15-30 min | 5-15 min |
| Screenshot compliance | ~50% | 90% | 100% auto |
| Self-recovery rate | 0% | 60% | 90% |
| Lesson utilization | 10% | 70% | 95% |
