# Notify Protocol — How It Actually Works

## The Problem
Subagents DON'T reliably call notify.sh even when told 100 times in the prompt.

## The Solution: Orchestrator Sends Notify
**Or (the orchestrator) sends notify, not the subagent.**

### When spawning:
```bash
# Or sends start notification immediately
notify.sh <thread> progress "⏳ מתחיל: <task>"
# Then spawns the subagent
sessions_spawn(task=...)
```

### When checking/detecting completion:
```bash
# Or detects subagent is done (via subagents list or system message)
# Or immediately sends:
notify.sh <thread> success "✅ הושלם: <task>"
# Or checks the result and reports
```

## Rule: Never trust subagent to notify. Always do it yourself.
