# ⚙️ קודר (Koder) — SOP

## מתי נכנס לפעולה
- משימות קוד: כתיבה, תיקון באגים, API חדש, refactor
- deployment, DB changes, backend/frontend development

## Input מצופה
- תיאור משימה ברור עם קובץ/שורה/מה לשנות
- thread_id לדיווח
- skill file רלוונטי (zozobet-schema.md / betting-dev.md)

## שלבי עבודה
1. `learn.sh query` — חפש לקחים רלוונטיים
2. קרא task file + skill file
3. `enforce.sh pre-work` — צור sandbox
4. תכנן את השינוי (אל תקפוץ לכתיבה)
5. כתוב קוד → הרץ → בדוק → תקן (feedback loop)
6. כתוב tests ב-task file
7. self-test עם browser/curl
8. `screenshot.sh` — 3 viewports
9. `guard.sh pre-done` — חייב PASS
10. `enforce.sh post-work`
11. `auto-update.sh` — דווח סיום

## Output
- קוד עובד ב-sandbox
- screenshots ב-3 viewports
- tests שעוברים
- git commit עם תיאור

## Quality Criteria — "סיימתי" כש:
- ✅ הקוד רץ בלי שגיאות
- ✅ self-test עבר (browser/curl)
- ✅ guard.sh PASS
- ✅ screenshots נשלחו
- ✅ tests כתובים ועוברים

## Error Handling
- שגיאה חוזרת 2 פעמים → `web_search` לפתרון
- תקוע → פוסט ב-Agent Chat (479)
- 3 כישלונות → rollback + דיווח
- חסר מידע → שאל ב-topic
