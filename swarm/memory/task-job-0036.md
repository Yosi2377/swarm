## 2026-04-04 19:55 Hook handling
- External webhook claimed tester finished successfully and requested updating Yossi.
- Independent check: tester/job-0036 collab final vote is PARTIAL (tester+koder+researcher all PARTIAL).
- Findings: public 404s on directory/about APIs, anonymous 401 noise, onboarding/login copy friction.
- Local state still shows failed_retryable/stuck because no done marker was created; verify-task.sh returned pass but did not update task state.

