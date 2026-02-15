# HEARTBEAT.md

## Delegation Queue
- Check /tmp/delegate-queue/ for pending .json files
- For each pending file: activate the target agent session via sessions_send
- Mark file as "activated" after sending
- This enables agent-to-agent delegation without orchestrator bottleneck

## Active Task Monitoring
- Check swarm/tasks.json for active tasks
- If any task is active for 10+ minutes with no updates → reactivate the agent
- If any task is stuck → try to unblock or split
- Post status update to General if tasks changed

## Learning Evolution
- Run `swarm/learn.sh evolve` to check for pattern-based skill generation
- Run `swarm/learn.sh report` to check agent scores
- If any agent score < 30%, flag it
