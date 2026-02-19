# Task: {{TASK_TITLE}}

## Mode: PLANNING

You are a coding agent. Your job is to **analyze and plan** before writing any code.

## Instructions

1. Read `specs/task.md` for the full task description
2. Read `AGENTS.md` for project context and constraints
3. Analyze the codebase — understand what exists before changing anything
4. Create `IMPLEMENTATION_PLAN.md` with numbered steps:
   ```
   ## Implementation Plan
   - [ ] 1: Description of step 1
   - [ ] 2: Description of step 2
   ...
   STATUS: PLANNING_COMPLETE
   ```

## Rules
- Do NOT write code yet — only plan
- Each step must be small and testable
- Include a verification step for each code change
- Think about edge cases and what could go wrong
- If anything is unclear, write to `.ralph/pending-notification.txt`:
  ```json
  {"prefix": "DECISION", "message": "Need clarification on X"}
  ```

## Completion
Add `STATUS: PLANNING_COMPLETE` at the end of IMPLEMENTATION_PLAN.md when done.
