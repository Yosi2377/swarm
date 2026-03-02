# SYSTEM v2 — Agent Task Runner Protocol

> **מבוסס על SYSTEM.md v4 + מערכת Task Runner אוטונומית**
> כל מה שב-SYSTEM.md עדיין בתוקף. מסמך זה מוסיף את זרימת העבודה האוטונומית.

---

## 🚨🚨🚨 חוק ברזל #1 — NOTIFY חובה 🚨🚨🚨

**הפקודה הראשונה שאתה מריץ בכל משימה:**
```bash
/root/.openclaw/workspace/swarm/notify.sh <THREAD_ID> progress "מתחיל לעבוד על: <תיאור>"
```

**הפקודה האחרונה שאתה מריץ בכל משימה:**
```bash
/root/.openclaw/workspace/swarm/notify.sh <THREAD_ID> success "✅ הושלם: <תיאור>"
# או:
/root/.openclaw/workspace/swarm/notify.sh <THREAD_ID> failed "❌ נכשל: <סיבה>"
```

**⛔ אם לא שלחת notify — המשימה לא נחשבת כסיימת!**
**⛔ אין תירוצים. notify קודם לכל דיווח אחר.**

---

## 🚀 זרימת עבודה חדשה — Task Runner

כשמקבלים משימת קוד, השתמשו ב-task-runner.sh:

```bash
/root/.openclaw/workspace/swarm/task-runner.sh <project_dir> "<task_description>" <agent_id> <thread_id>
```

### מה זה עושה:
1. **Setup** — יוצר branch מ-main/master: `fix/{agent}-{task_id}`
2. **Baseline** — מריץ טסטים קיימים (כדי לזהות regression אח"כ)
3. **Work Loop** — עד 5 ניסיונות עם self-healing:
   - עבודה → טסטים → עובר? סיים. נכשל? → reflection → נסה שוב
   - אותה שגיאה 3 פעמים → מחליף אסטרטגיה אוטומטית (stash + branch חדש)
4. **QA Check** — בדיקת regression, lint, git diff review
5. **Report** — סיכום מפורט עם diff, תוצאות טסטים, branch למרג'

### כלים נלווים:

| כלי | שימוש | פקודה |
|-----|-------|-------|
| QA Guard | בדיקת איכות אחרי שינוי | `qa-guard.sh <project_dir> [baseline]` |
| Reflect | ניתוח כישלון | `reflect.sh <error> <attempt> <prev_file>` |
| Task Runner | זרימה מלאה | `task-runner.sh <dir> <desc> <agent> <thread>` |
| Notify | עדכון אוטומטי ליוסי | `notify.sh <thread> <status> <message>` |

### סטטוסי Notify:
- `progress` — "עובד על X..." (כל כמה דקות)
- `success` — "✅ הושלם — branch X מוכן"
- `failed` — "❌ נכשלתי אחרי 5 ניסיונות"
- `stuck` — "🆘 נתקעתי, צריך עזרה"

**חובה:** שלח notify בכל מעבר שלב — לא רק בסוף!

---

## ⛔ חוקים חדשים — חובה!

### 1. לולאת עבודה עם Reflection
```
כתוב קוד → הרץ טסטים → נכשל? → reflect.sh → תקן → חזור
```
**אסור** לנסות את אותו דבר פעמיים. אחרי כישלון, **חובה** לקרוא את ה-reflection ולנסות גישה אחרת.

Reflections נשמרות ב: `/tmp/task-{id}-reflections.jsonl`

### 2. qa-guard.sh חובה לפני דיווח סיום
```bash
# לפני שאומרים "✅ הושלם":
RESULT=$(/root/.openclaw/workspace/swarm/qa-guard.sh /path/to/project /tmp/task-{id}-baseline.json)
echo "$RESULT" | jq '.status'
# חייב להיות "pass"! אם "fail" או "regression" — תקן קודם.
```

### 3. דיווח חייב לכלול:
- **Screenshot** — proof ויזואלי שזה עובד
- **git diff --stat** — מה בדיוק השתנה
- **תוצאות QA** — pass/fail + פירוט
- **Branch name** — למרג'

### 4. קבצי Temp למשימה
| קובץ | מיקום | תוכן |
|-------|--------|-------|
| Baseline | `/tmp/task-{id}-baseline.json` | תוצאות טסטים לפני שינוי |
| Reflections | `/tmp/task-{id}-reflections.jsonl` | כל ה-reflections (שורה=JSON) |
| QA Result | `/tmp/task-{id}-qa.json` | תוצאת QA אחרונה |
| State | `/tmp/task-{id}-state.json` | מצב נוכחי של המשימה |

---

## 🔄 Self-Healing — איך זה עובד

```
ניסיון 1: שינוי → טסט נכשל → reflection: "syntax error בשורה 42"
ניסיון 2: תיקון syntax → טסט נכשל → reflection: "import חסר"
ניסיון 3: הוספת import → טסט עובר! ✅ → QA check → דיווח
```

**אם אותה שגיאה חוזרת 3 פעמים:**
```
→ git stash (שומר עבודה נוכחית)
→ branch חדש מ-main
→ גישה שונה לחלוטין
```

---

## 📋 Flow מלא — צ'קליסט לסוכן

- [ ] קרא `SYSTEM.md` + `SYSTEM-v2.md`
- [ ] `learn.sh query "keywords"` — בדוק לקחים
- [ ] הרץ `task-runner.sh` או עקוב אחרי ה-flow ידנית
- [ ] עבוד בלולאה: קוד → טסט → reflect → תקן
- [ ] `qa-guard.sh` — חייב pass
- [ ] Screenshot + git diff
- [ ] דווח דרך `send.sh`
- [ ] שלח עדכון אוטומטי: `notify.sh <thread> success/failed/progress "הודעה"`
- [ ] **חובה!** `learn.sh lesson <agent> <severity> <impact> "<what>" "<lesson>"` — שמור לקח
- [ ] **חובה!** `learn.sh score <agent> <task_id> <pass|partial|fail> "<notes>"` — דרג ביצוע
- [ ] `pieces-realtime.sh "agent:<id>" "<summary>"` — שמור ל-Pieces LTM
- [ ] `notify.sh <thread> <status> "<message>"` — עדכן את יוסי

## ⚠️ למידה אוטומטית — חובה אחרי כל משימה!
אם השתמשת ב-task-runner.sh — הלמידה אוטומטית.
אם עבדת ידנית — **חייב** לקרוא ל-learn.sh בסוף:
```bash
# הצלחה:
/root/.openclaw/workspace/swarm/learn.sh lesson koder normal 1.0 "Fixed X" "Solution was Y"
# כישלון:
/root/.openclaw/workspace/swarm/learn.sh lesson koder important 0.8 "Failed X" "Problem was Y"
```
