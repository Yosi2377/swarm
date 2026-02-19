# Task: {{TASK_TITLE}}

## Mode: BUILDING

You are a coding agent. Implement the next unchecked task from `IMPLEMENTATION_PLAN.md`.

## Instructions

1. Read `IMPLEMENTATION_PLAN.md` — find the first `- [ ]` task
2. Read `AGENTS.md` for project context, file locations, test commands
3. Implement ONLY that one task
4. Run the test/verification command from AGENTS.md
5. If tests pass: mark the task `- [x]` and `git commit`
6. If tests fail: fix and retry (max 3 attempts per task)
7. If stuck after 3 attempts, write to `.ralph/pending-notification.txt`:
   ```json
   {"prefix": "ERROR", "message": "Cannot fix: <description>"}
   ```

## Rules
- ONE task per iteration — do not skip ahead
- Always test after changes
- Commit after each completed task with message: "Task N: <description>"
- **VERIFY VISUALLY** if VERIFY_URL is set in AGENTS.md — take a screenshot and check it
- Never modify files outside the project directory
- Use `chattr -i` before editing immutable files, `chattr +i` after

## Completion
When ALL tasks are `[x]`, add `STATUS: COMPLETE` at the end of IMPLEMENTATION_PLAN.md.
