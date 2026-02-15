# Task Template

Use this template when creating task files for agents.

## Template: `/swarm/tasks/<task-id>.md`

```markdown
# Task: [שם המשימה]
**Topic**: #[thread_id]
**Agent**: [koder/shomer/tzayar/worker/researcher]
**Priority**: [urgent/high/normal/low]
**Status**: pending → active → review → done

## Description
[מה צריך לעשות — תיאור ברור וקצר]

## Skill Required
Read: `swarm/skills/[relevant-skill].md`

## Files to Modify
- `path/to/file1` — [מה לשנות]
- `path/to/file2` — [מה לשנות]

## Acceptance Criteria
- [ ] [קריטריון 1]
- [ ] [קריטריון 2]
- [ ] Screenshots sent as proof
- [ ] Code reviewed by שומר

## Context
[מידע נוסף שהסוכן צריך — API endpoints, DB schema, etc.]

## Sandbox
- URL: [sandbox URL for testing]
- Service: [systemd service to restart]
```

## Flow
1. **Orchestrator** creates task file + topic
2. **Orchestrator** activates agent with: "קרא את `swarm/tasks/<id>.md` והתחל לעבוד"
3. **Agent** reads task file + relevant skill → works in sandbox
4. **Agent** posts screenshots in topic when done
5. **שומר** reviews `git diff`
6. **User** approves → orchestrator deploys to production
