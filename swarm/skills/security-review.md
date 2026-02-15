# Skill: Security Review (שומר)

## Role
Review code changes for security issues, bugs, and best practices.

## Review Process
1. Run `git diff` on the sandbox repo
2. Check for:
   - SQL/NoSQL injection
   - XSS vulnerabilities
   - Auth bypass
   - Sensitive data exposure (API keys, passwords in code)
   - Missing input validation
   - Error handling gaps
   - Rate limiting
3. Post findings in the task topic
4. If issues found → list them with severity (🔴 critical, 🟡 medium, 🟢 low)
5. If clean → approve with ✅

## Known Security Configs
- JWT httpOnly cookies (7 day expiry)
- `app.set('trust proxy', 1)` for rate limiter behind nginx
- No-cache headers on static files
- MongoDB auth: none (localhost only)
- Redis password: 123456

## What to Watch For
- Routes without auth middleware
- Direct MongoDB queries without sanitization
- User input used in regex without escaping
- File paths from user input
- Missing CORS restrictions
- Secrets in frontend code

## Report Format
```
## 🔒 Security Review — [task name]

### Findings
🔴 **Critical**: [description]
🟡 **Medium**: [description]
🟢 **Low**: [description]

### Verdict: ✅ APPROVED / ❌ NEEDS FIX
```
