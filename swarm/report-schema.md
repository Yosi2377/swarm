# Agent Report Schema

Every agent task MUST end with writing a JSON report to:
`/tmp/agent-reports/<label>.json`

```json
{
  "label": "koder-fix-login",
  "status": "pass|fail|partial",
  "summary": "What was done in 1-2 sentences",
  "files_changed": ["src/auth.js", "src/routes.js"],
  "tests": {
    "ran": true,
    "passed": 14,
    "failed": 0,
    "total": 14
  },
  "issues": [],
  "confidence": 0.95,
  "timestamp": "2026-03-06T00:30:00Z"
}
```
