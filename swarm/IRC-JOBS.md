# IRC job-based orchestration mode

This swarm can run in IRC mode using internal `job-*` identifiers instead of Telegram topics.

## Core rules
- Every task gets a unique internal `jobId` like `job-0007`
- Small/short tasks stay in `#myops`
- Bigger or multi-agent tasks are promoted to `#job-0007`
- All IRC messages must start with `[job-0007]`
- Final summaries return to `#myops`

## Runtime config
See `swarm/runtime.json`.

Current defaults:
- transport: `irc`
- ops channel: `#myops`
- dedicated prefix: `#job-`

## Main scripts

### Open a job
```bash
swarm/job-open.sh <agent_id> "title" [task_description]
```
Returns:
```bash
job-0007 #myops
```
or:
```bash
job-0008 #job-0008
```

### Send an update
```bash
swarm/send.sh <agent_id> <job_id> "message"
```

### Close a job
```bash
swarm/job-close.sh <agent_id> <job_id> "✅ summary"
```

## Compatibility
- `create-topic.sh` becomes a job allocator when `transport=irc`
- `send.sh` routes by `jobId` in IRC mode
- `dispatch-task.sh` reclassifies the job as `#myops` vs `#job-*` using task text

## Files
- `swarm/jobs/index.json` — next job counter
- `swarm/jobs/job-0007.json` — per-job state, channel, history, summary
