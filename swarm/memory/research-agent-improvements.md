# מחקר מקיף: שיפור מערכת הסוכנים — TeamWork Swarm
**תאריך:** 2026-02-15
**חוקר:** 🔍 Researcher

---

## 1. ניתוח פריימוורקים מתחרים

### CrewAI
- **מה עושה:** פריימוורק leading לסוכנים אוטונומיים. ארכיטקטורה של Flows (ניהול state + event-driven) + Crews (צוותי סוכנים).
- **מה שיש להם ואין לנו:**
  - **Flows** — state management רשמי בין שלבים (אנחנו משתמשים בקבצי task-*.md)
  - **Role-Playing Agents** — הגדרות role מובנות עם goals + tools per agent
  - **Task Delegation מובנה** — delegations בתוך crew אוטומטיים
  - **100K+ מפתחים** — אקוסיסטם ענק
- **מקור:** https://docs.crewai.com

### AutoGen (Microsoft)
- **מה עושה:** פריימוורק לשיחות בין סוכנים. 3 שכבות: Studio (UI ללא קוד), AgentChat (programming), Core (event-driven scalable).
- **מה שיש להם:**
  - **AutoGen Studio** — UI ויזואלי לפרוטוטייפים בלי קוד (אנחנו עם dashboard בסיסי)
  - **Event-Driven Core** — ניהול scalable של סוכנים
  - **MCP Integration** — McpWorkbench מובנה
  - **Docker Code Executor** — הרצת קוד בcontainer (אנחנו עם sandbox בתיקיות)
- **מקור:** https://microsoft.github.io/autogen/

### LangGraph
- **מה עושה:** פריימוורק low-level לאורקסטרציה של סוכנים stateful. דגש על durable execution.
- **מה שיש להם:**
  - **Durable Execution** — סוכנים ששורדים crashes וממשיכים מאיפה שעצרו
  - **Human-in-the-Loop מובנה** — יכולת להפסיק, לבדוק state, ולהמשיך
  - **Comprehensive Memory** — short-term working + long-term cross-session
  - **LangSmith Debugging** — tracing ו-debugging ויזואלי של runs
- **מקור:** https://docs.langchain.com/oss/python/langgraph/overview

### OpenAI Swarm → Agents SDK
- **מה עושה:** פריימוורק קליל מבוסס 2 primitives: Agents + Handoffs. Swarm הוחלף ע"י Agents SDK (production-ready).
- **מה שיש להם:**
  - **Handoffs** — העברת שליטה פשוטה בין סוכנים (כמו delegate אבל native)
  - **Guardrails** — בדיקות בטיחות על input/output
  - **Sessions** — ניהול היסטוריית שיחות אוטומטי
  - **Tracing** — מעקב מובנה אחרי runs
- **מקור:** https://github.com/openai/openai-agents-python

### AWS Agent Squad (Multi-Agent Orchestrator)
- **מה עושה:** פריימוורק קל לאורקסטרציה של סוכני AI עם routing חכם.
- **מה שיש להם:**
  - **Intent Classification** — ניתוב אוטומטי לסוכן הנכון ע"פ context
  - **Dual Language** — Python + TypeScript
  - **Context Management** — ניהול הקשר בין שיחות
  - **Streaming Support** — תגובות streaming מסוכנים שונים
- **מקור:** https://github.com/awslabs/agent-squad

---

## 2. Best Practices — ממצאים מרכזיים

### תקשורת בין סוכנים
| Pattern | תיאור | רלוונטיות |
|---------|--------|-----------|
| **Structured Handoffs** | העברת task עם schema קבוע (inputs, outputs, constraints) | גבוהה — אנחנו משתמשים בטקסט חופשי |
| **Shared State Store** | DB/Redis משותף במקום קבצים | גבוהה — קבצים איטיים ולא atomic |
| **Event Bus** | pub/sub בין סוכנים | בינונית — אנחנו עם send.sh + delegate |
| **Guardrails** | validation על input/output של כל סוכן | גבוהה — אין לנו |

### זיכרון ולמידה
| Pattern | תיאור | רלוונטיות |
|---------|--------|-----------|
| **Vector Memory** | embedding-based retrieval במקום text search | גבוהה |
| **Knowledge Graph** | קשרים מובנים בין entities | בינונית |
| **Episodic Memory** | זיכרון של "פרקים" שלמים (task from start to end) | גבוהה |
| **Shared Context Pool** | context משותף שכל הסוכנים יכולים לקרוא/לכתוב | גבוהה |

### בדיקות ואמינות
| Pattern | תיאור | רלוונטיות |
|---------|--------|-----------|
| **Self-Verification** | סוכן מריץ assertion על הoutput שלו | גבוהה — יש לנו browser testing |
| **Peer Review** | סוכן אחד בודק את עבודת סוכן אחר | גבוהה |
| **Checkpoint/Rollback** | שמירת state points לחזרה | יש לנו (enforce.sh) |
| **Circuit Breaker** | עצירה אוטומטית אחרי X כשלונות | בינונית |

---

## 3. מה יש לנו vs מה חסר

### ✅ יש לנו (ועובד טוב)
- Orchestrator + role-based agents (5 סוכנים מוגדרים)
- Task management (task.sh + tasks.json)
- Sandbox enforcement (enforce.sh)
- Learning system (learn.sh — lessons, scores, evolution)
- Communication (send.sh + delegate.sh)
- Dashboard (tworkswarm.duckdns.org)
- Skills system (per-project knowledge)
- Browser-based self-testing

### ❌ חסר לנו (מה שמתחרים עושים)
1. **Structured handoffs** — אנחנו מעבירים טקסט חופשי, לא schema
2. **Guardrails** — אין validation על output של סוכנים
3. **Durable execution** — סוכן שנופל לא ממשיך אוטומטית
4. **Vector memory / RAG** — הlessons system הוא text-based search
5. **Visual debugging / tracing** — Dashboard בסיסי, אין timeline של runs
6. **Intent classification** — Orchestrator מנתב ידנית, לא אוטומטי
7. **Parallel task execution** — delegate עובד סדרתי (heartbeat מפעיל)
8. **Output quality scoring** — learn.sh עושה binary success/fail, לא quality
9. **Cross-task context sharing** — סוכנים לא יודעים מה סוכנים אחרים עושים
10. **Auto-retry with escalation** — אין retry חכם עם שינוי אסטרטגיה

---

## 4. ClawHub Skills
ClawHub (clawhub.ai) — לא נמצאו skills ספציפיים למערכות multi-agent. הפלטפורמה עדיין בשלב מוקדם.

---

## 5. 🏆 TOP 10 רעיונות — ממוינים לפי השפעה × קלות יישום

| # | רעיון | השפעה | קלות | ציון | תיאור |
|---|-------|-------|------|------|-------|
| **1** | **Structured Task Schema** | 🔴 גבוהה | 🟢 קל | ⭐⭐⭐⭐⭐ | להגדיר JSON schema קבוע ל-task handoff: `{task, inputs, expected_output, constraints, deadline}`. מונע אי-הבנות, מאפשר validation אוטומטי. פשוט ליישם — רק לשנות delegate.sh ו-task.sh. |
| **2** | **Peer Review אוטומטי** | 🔴 גבוהה | 🟢 קל | ⭐⭐⭐⭐⭐ | כשסוכן מדווח "done" — סוכן אחר (שומר לאבטחה, קודר לקוד) בודק אוטומטית לפני שמגיע לuser. יש כבר את התשתית (delegate.sh), רק צריך flow חדש. |
| **3** | **Shared Context File (live)** | 🔴 גבוהה | 🟢 קל | ⭐⭐⭐⭐⭐ | קובץ `swarm/memory/shared/active-context.md` שכל סוכן מעדכן ויכול לקרוא — מה קורה עכשיו בכל task. מונע עבודה כפולה, מאפשר סינרגיה. קיים כבר `memory/shared/` — רק צריך convention. |
| **4** | **Auto-Retry with Strategy Change** | 🔴 גבוהה | 🟡 בינוני | ⭐⭐⭐⭐ | כשtask נכשל, במקום לעצור — לנסות עם אסטרטגיה אחרת (מודל אחר, thinking level אחר, פיצול המשימה). לשלב ב-task.sh עם retry counter ו-strategy rotation. |
| **5** | **Output Quality Scoring** | 🟡 בינונית | 🟢 קל | ⭐⭐⭐⭐ | במקום binary success/fail — לתת ציון 1-10 לכל output (שלמות, נכונות, זמן). learn.sh כבר תומך ב-scores, רק צריך להרחיב ולהוסיף rubric. |
| **6** | **Guardrails Layer** | 🔴 גבוהה | 🟡 בינוני | ⭐⭐⭐⭐ | סקריפט `guard.sh` שבודק output לפני שליחה: האם יש קוד production שנערך ישירות? האם screenshots צורפו? האם task file עודכן? אפשר להריץ ב-enforce.sh. |
| **7** | **Task Timeline Dashboard** | 🟡 בינונית | 🟡 בינוני | ⭐⭐⭐ | להוסיף ל-dashboard: timeline ויזואלי של כל task — מתי התחיל, שלבים, מתי נגמר. ליצור מ-logs שכבר קיימים (`swarm/logs/`). |
| **8** | **Episodic Memory** | 🟡 בינונית | 🟡 בינוני | ⭐⭐⭐ | לשמור task שלם כ"פרק" — הinput, הprocess, הoutput, הlessons. ואז כשtask דומה מגיע — לשלוף את הפרק הרלוונטי כcontext. לבנות מעל learn.sh + task files. |
| **9** | **Smart Intent Router** | 🟡 בינונית | 🔴 קשה | ⭐⭐ | במקום routing ידני ב-Orchestrator — classifier אוטומטי שמנתב לסוכן הנכון. דורש prompt engineering או fine-tuning. כרגע הrouting ידני עובד טוב, שווה להשקיע רק בscale. |
| **10** | **Vector Memory / RAG** | 🟡 בינונית | 🔴 קשה | ⭐⭐ | להחליף את text search ב-learn.sh ב-vector embeddings. דורש DB חדש (ChromaDB/Qdrant), indexing pipeline. שווה כשיהיו הרבה lessons (+100). כרגע learn.sh מספיק. |

---

## 6. המלצות ליישום מיידי (השבוע)

### Quick Wins (שעות בודדות כל אחד):
1. **Structured Task Schema** — להגדיר template ב-`swarm/templates/task-schema.json`
2. **Shared Active Context** — ליצור `swarm/memory/shared/active-context.md` עם conventions
3. **Output Quality Rubric** — להרחיב learn.sh score לקבל ציון 1-10

### שבוע הבא:
4. **Peer Review flow** — להוסיף `--review` flag ל-task.sh
5. **Guardrails script** — `guard.sh` שרץ לפני post-work

### חודש הבא:
6. **Auto-retry** — strategy rotation ב-task.sh
7. **Timeline dashboard** — visualization מ-logs

---

## 7. מקורות

| מקור | URL |
|------|-----|
| CrewAI Docs | https://docs.crewai.com/en/introduction |
| AutoGen (Microsoft) | https://microsoft.github.io/autogen/stable/ |
| LangGraph | https://docs.langchain.com/oss/python/langgraph/overview |
| OpenAI Agents SDK | https://github.com/openai/openai-agents-python |
| AWS Agent Squad | https://github.com/awslabs/agent-squad |
| OpenAI Swarm (archived) | https://github.com/openai/swarm |
| ClawHub | https://clawhub.ai |

---

*דוח זה נשמר ב: `swarm/memory/research-agent-improvements.md`*
