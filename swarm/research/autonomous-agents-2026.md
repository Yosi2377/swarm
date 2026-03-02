# מחקר: מערכות סוכנים אוטונומיים שמתקנים את עצמם
**תאריך:** 2026-03-02  
**חוקר:** סוכן מחקר  
**מקורות:** Anthropic, Princeton/Stanford (SWE-agent), Cognition (Devin), Lilian Weng (OpenAI)

---

## סיכום מנהלים

המחקר מזהה קונצנזוס ברור בתעשייה לשנת 2025-2026: **הפשטות מנצחת**. המערכות הכי מוצלחות לקידוד אוטונומי הן לא הכי מורכבות — הן הכי פשוטות שעדיין עובדות. mini-SWE-agent (100 שורות Python) משיג 74%+ על SWE-bench verified, מה שמוכיח שהערך האמיתי הוא ב-LLM עצמו, לא ב-scaffold.

**שלוש תובנות מפתח:**
1. **לולאת Agent פשוטה** (LLM → כלים → תוצאה → חזרה ל-LLM) עדיפה על ארכיטקטורות מורכבות
2. **Git branch per attempt** + טסטים אוטומטיים = המנגנון הכי אמין ל-self-healing
3. **Evaluator-Optimizer pattern** (מ-Anthropic) הוא הדפוס הנכון לתיקון עצמי

---

## דפוסים שעובדים (עם מקורות)

### 1. לולאת Agent בסיסית (ReAct Loop)
**מקור:** Anthropic "Building Effective Agents", SWE-agent (NeurIPS 2024)

```
while not done:
    observation = environment.get_state()
    action = llm.decide(history + observation)
    result = environment.execute(action)
    history.append(action, result)
    if success_criteria_met(result):
        done = True
    if iterations > max_iterations:
        done = True  # safety stop
```

**למה זה עובד:**
- ה-LLM מקבל "ground truth" מהסביבה בכל צעד (תוצאות הרצת קוד, שגיאות)
- היסטוריה ליניארית — קל לדבג, קל לעשות fine-tuning
- Anthropic: "Agents are typically just LLMs using tools based on environmental feedback in a loop"

### 2. Bash-Only Agent (ללא כלים מותאמים)
**מקור:** mini-SWE-agent (Princeton/Stanford, 2025)

- **100 שורות Python בלבד** + subprocess.run לכל פעולה
- אין tool-calling interface — הכל דרך bash
- כל פעולה עצמאית (לא shell session רצופה) — יציבות מדהימה
- **74%+ על SWE-bench verified** — ביצועים שווים ל-agents מורכבים פי 100
- משתמשים: Meta, NVIDIA, IBM, Stanford, Princeton

**תובנה קריטית:** "Every action is completely independent (as opposed to keeping a stateful shell session running). This makes it trivial to execute in sandboxes and to scale up effortlessly." — זה game-changer ליציבות.

### 3. Agent-Computer Interface (ACI) מעולה
**מקור:** SWE-agent paper (arXiv:2405.15793), Anthropic

- **השקעה בעיצוב הכלים > השקעה בפרומפט הראשי**
- Anthropic שיפרו ביצועים רק ע"י שינוי כלים לדרוש absolute paths במקום relative
- Rule of thumb: "Think about how much effort goes into HCI, and plan to invest just as much in ACI"
- **Poka-yoke** — עיצוב כלים כך שקשה לטעות בהם

### 4. Evaluator-Optimizer Pattern (Self-Healing)
**מקור:** Anthropic "Building Effective Agents"

```
while not evaluator.approve(result):
    result = generator.improve(result, evaluator.feedback)
```

- LLM אחד מייצר פתרון, LLM שני מעריך ונותן feedback
- **עובד כש:**
  - יש קריטריונים ברורים להערכה (טסטים עוברים? lint נקי?)
  - ה-LLM יכול לתת feedback מועיל (כמו code review)
- **מושלם לקוד** — כי טסטים נותנים הערכה אובייקטיבית

### 5. Orchestrator-Workers Pattern
**מקור:** Anthropic, Claude Code sub-agents

- Orchestrator מפרק משימה למשימות משנה דינמית
- Workers עובדים במקביל על קבצים/תחומים שונים
- Orchestrator מסנתז תוצאות
- **חיוני לשינויים multi-file** — מספר הקבצים לא ידוע מראש

### 6. Reflexion — למידה מכישלונות
**מקור:** Shinn & Labash 2023 (arXiv:2303.11366), Lilian Weng

- אחרי כל כישלון: ה-agent מייצר "reflection" — מה השתבש ואיך לתקן
- Reflections נשמרות ב-working memory (עד 3) ומשמשות כ-context לניסיון הבא
- **מזהה שני סוגי כישלונות:** planning לא יעיל, והזיות (חזרה על אותן פעולות)

### 7. Git Branch Per Fix
**דפוס נפוץ בפרקטיקה:**

```bash
git checkout -b fix/task-123-attempt-1
# agent works...
# if tests fail:
git stash && git checkout -b fix/task-123-attempt-2
# try different approach
```

- כל ניסיון ב-branch נפרד — קל לחזור אחורה
- מאפשר השוואה בין גישות
- **Regression protection** — main branch תמיד נקי

---

## דפוסים שלא עובדים

### ❌ 1. Frameworks מורכבים מדי
**מקור:** Anthropic

> "The most successful implementations weren't using complex frameworks or specialized libraries. Instead, they were building with simple, composable patterns."

- שכבות אבסטרקציה מסתירות את מה שקורה באמת
- קשה לדבג כשאתה לא מבין את ה-prompts הבסיסיים
- **המלצה:** התחל עם API ישיר, הוסף framework רק אם צריך

### ❌ 2. Shell Session רצופה (Stateful)
**מקור:** mini-SWE-agent FAQ

- Shell session שנשמרת בין פעולות = מקור לבאגים ואי-יציבות
- שינויי directory, משתני סביבה, processes שנתקעים
- **subprocess.run לכל פעולה** עדיף בהרבה

### ❌ 3. כלים עם Relative Paths
**מקור:** Anthropic SWE-bench experience

- ה-agent מתבלבל אחרי cd לתיקייה אחרת
- **תמיד absolute paths** — 100% דיוק

### ❌ 4. אוטונומיה מלאה ללא guardrails
**מקור:** Anthropic

> "The autonomous nature of agents means higher costs, and the potential for compounding errors."

- ללא max_iterations, agent יכול להיתקע בלולאה אינסופית
- ללא sandboxing, agent יכול לשבור דברים
- **חובה:** תנאי עצירה, סביבה מבודדת, checkpoints אנושיים

### ❌ 5. Tool-calling interface מורכב כשלא צריך
**מקור:** mini-SWE-agent

- agents עם 20 כלים מותאמים לא בהכרח טובים יותר מ-agent עם bash בלבד
- ככל שה-LLM חזק יותר, הוא צריך פחות כלים מותאמים
- "Just tell the LM to figure it out rather than spending time to implement it in the agent"

### ❌ 6. הוספת מורכבות מוקדם מדי
**מקור:** Anthropic

> "Start with simple prompts, optimize them with comprehensive evaluation, and add multi-step agentic systems only when simpler solutions fall short."

---

## ארכיטקטורה מומלצת למערכת שלנו

### מבנה כללי: Orchestrator + Self-Healing Workers

```
┌─────────────────────────────────────┐
│          ORCHESTRATOR (אור)          │
│  מקבל משימה → מפרק → מחלק לסוכנים  │
└──────────┬──────────────────────────┘
           │
    ┌──────┴──────┐
    ▼             ▼
┌────────┐  ┌────────┐
│ KODER  │  │ BODEK  │
│ Worker │  │  QA    │
└───┬────┘  └───┬────┘
    │           │
    ▼           ▼
┌─────────────────────┐
│   SANDBOX (Docker)   │
│  - Git repo clone   │
│  - Branch per task   │
│  - Test suite        │
└─────────────────────┘
```

### זרימת עבודה מפורטת:

```
1. ORCHESTRATOR מקבל משימה
   ↓
2. יוצר branch: fix/task-{id}
   ↓
3. שולח ל-KODER עם הנחיות ברורות
   ↓
4. KODER עובד בלולאה (max 5 iterations):
   a. כותב/עורך קוד
   b. מריץ טסטים (pytest/jest)
   c. אם עובר → סיים
   d. אם נכשל → קורא שגיאות, מנסה גישה אחרת
   e. אם נתקע (3 כישלונות באותה גישה) → מחליף אסטרטגיה
   ↓
5. KODER מדווח "סיימתי" / "נתקעתי"
   ↓
6. BODEK (QA) מריץ:
   a. את כל הטסטים (regression)
   b. lint/type checking
   c. בודק שאין שינויים לא רצויים (git diff review)
   ↓
7. אם BODEK מוצא בעיות → חוזר ל-KODER עם feedback ספציפי
   ↓
8. אם הכל עובר → ORCHESTRATOR מדווח + מבקש אישור merge
```

### Self-Healing Loop בתוך ה-Worker:

```python
def self_healing_loop(task, max_attempts=5):
    strategies = []
    for attempt in range(max_attempts):
        # Try to solve
        result = agent.solve(task, avoid=strategies)
        
        # Run tests
        test_result = run_tests()
        
        if test_result.passed:
            return Success(result)
        
        # Reflect on failure
        reflection = agent.reflect(
            task=task,
            attempt=result,
            error=test_result.errors,
            previous_strategies=strategies
        )
        strategies.append(reflection)
        
        # If same error 3 times, escalate
        if repeated_error(test_result, history):
            return Escalate(reflection)
    
    return MaxAttemptsReached(strategies)
```

---

## המלצות טכניות ספציפיות

### 1. Sandbox חובה
- **Docker container** לכל משימה — בידוד מלא
- Clone של ה-repo בתוך ה-container
- **אף פעם לא על production** — רק sandbox → review → merge

### 2. Git כ-Safety Net
- Branch per task: `fix/{agent}-{task-id}-attempt-{n}`
- Commit אחרי כל שינוי מוצלח (checkpoint)
- `git stash` + branch חדש בהחלפת אסטרטגיה
- **git diff** לפני כל דיווח סיום — וידוא שרק שינויים רלוונטיים

### 3. טסטים כ-Oracle
- **הרץ טסטים קיימים** לפני כל שינוי (baseline)
- **הרץ שוב אחרי** — regression check אוטומטי
- Agent צריך לכתוב טסטים חדשים למה שהוא בנה
- **כלל: אם אין טסטים, תכתוב טסטים קודם**

### 4. ארכיטקטורת כלים
- **Bash בלבד** (בהשראת mini-SWE-agent) — פשוט ויציב
- **subprocess.run** לכל פעולה (לא stateful shell)
- **Absolute paths** תמיד
- כלים מתועדים היטב עם דוגמאות

### 5. הגבלות ו-Guardrails
- **max_iterations = 5** לכל משימה (ניתן להגדלה)
- **timeout** לכל פעולת bash (60 שניות default)
- **max_file_changes = 10** — התראה אם agent משנה יותר מדי קבצים
- **forbidden paths** — אין גישה ל-config/secrets/production

### 6. Memory ו-Context
- **Reflection log** — כל כישלון ותובנה נשמרים בקובץ
- **Strategy blacklist** — גישות שנכשלו לא מנוסות שוב
- **Cross-task learning** — שמירת דפוסים שעבדו ב-memory/

### 7. Human-in-the-Loop
- **Checkpoint אנושי** לפני merge ל-main
- Agent יכול לבקש עזרה אם נתקע
- **Screenshot/diff** חובה בדיווח סיום — לא רק "הושלם"

### 8. מודלים
- **Orchestrator:** Claude Opus/Sonnet — צריך reasoning חזק
- **Workers:** Claude Sonnet — balance של מהירות ואיכות
- **QA/Evaluator:** Claude Sonnet — יכולת ביקורתית טובה
- **Routing:** Claude Haiku — מהיר וזול לסיווג משימות

---

## מקורות

1. **Anthropic** — "Building Effective AI Agents" (2024) — https://www.anthropic.com/engineering/building-effective-agents
2. **SWE-agent** — Yang et al., NeurIPS 2024 — arXiv:2405.15793
3. **mini-SWE-agent** — Princeton/Stanford, 2025 — https://mini-swe-agent.com
4. **Devin** — Cognition AI, 2024 — https://cognition.ai/blog/introducing-devin
5. **LLM Powered Autonomous Agents** — Lilian Weng (OpenAI), 2023 — https://lilianweng.github.io/posts/2023-06-23-agent/
6. **Reflexion** — Shinn & Labash, 2023 — arXiv:2303.11366
7. **ReAct** — Yao et al., 2023 — arXiv:2210.03629
8. **Claude Code Documentation** — https://code.claude.com/docs
