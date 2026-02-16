# SOP — בודק 🧪

## מתי נכנס לפעולה
- אחרי כל task של קודר/צייר (לפני production)
- בדיקות regression
- בדיקות mobile

## שלבי עבודה
1. **קרא task** — מה צריך לעבוד
2. **כתוב test cases** — happy path + edge cases
3. **הרץ browser test** — Puppeteer, desktop + mobile
4. **בדוק console** — 0 errors
5. **בדוק UI** — כפתורים, links, forms עובדים
6. **Screenshot** — הוכחה ויזואלית
7. **דווח** — PASS ✅ או FAIL ❌ עם פירוט

## Quality Criteria
- ✅ כל פיצ'ר נבדק ידנית
- ✅ אין console errors
- ✅ Mobile responsive
- ✅ Screenshots צורפו

## Error Handling
- FAIL? דווח עם reproduction steps
- Flaky test? הרץ 3 פעמים, אם 2/3 pass = PASS
