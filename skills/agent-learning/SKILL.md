---
name: agent-learning
description: Agent learning and evaluation system. Track lessons from successes/failures, score agents, auto-generate skills from patterns, evaluate task completion with browser tests. Use when managing agent performance, reviewing lessons, checking scores, or improving agent workflows.
---

# Agent Learning System

Track what agents learn, score their performance, and evolve knowledge into reusable skills.

## Commands

```bash
# Query lessons before starting work
learn.sh query "keywords"

# Record a lesson after task
learn.sh lesson <agent> <critical|medium|low> "title" "description"

# Record success/failure
learn.sh score <agent> success|fail "optional description"

# View all scores
learn.sh report

# Evolve patterns into skills
learn.sh evolve
```

## Data Files

| File | Purpose |
|------|---------|
| `learning/lessons.json` | All lessons with severity, agent, timestamp |
| `learning/scores.json` | Agent success/fail counts and percentages |
| `learning/patterns.json` | Auto-detected patterns for skill generation |
| `learning/checkpoints/` | Task completion checkpoints |

## Evaluation System

### Browser Evaluator
```bash
# Evaluate task with browser tests
evaluator.sh <project> <thread_id>

# Direct browser test
node browser-eval.js <url> [test-file.json]
node smart-eval.js <url> --task <task-file.md>
```

### Task File Browser Tests Format
```markdown
## Browser Tests
- exists: .c-match → "Match rows visible"
- count: .c-odds → min:10 → "Has odds buttons"
- click: .b365-btn → "Clicking odds works"
- text: .bal → contains:₪ → "Balance shows currency"
- noErrors → "No JS console errors"
```

## Critical Lessons (Meta)

1. **Agents don't query lessons on their own** — orchestrator must query AND inject into task prompts
2. **learn.sh lesson requires all 4 args** — agent, severity, title, description
3. **Evaluator needs correct selectors** — must match actual site CSS classes
4. **Screenshots are mandatory** — never report done without visual proof

## Integration with Orchestrator

Before sending any task:
```bash
# 1. Query relevant lessons
LESSONS=$(learn.sh query "keywords for this task")

# 2. Include in task prompt
"⚠️ Lessons from learning system:
$LESSONS
Read these before starting!"
```
