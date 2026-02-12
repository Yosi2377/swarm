# 🐝 Swarm HQ

Multi-agent coordination system. Or (אור) is the coordinator.

## Structure
```
swarm/
├── SYSTEM.md          # System prompt for all sub-agents
├── README.md          # This file
├── registry/
│   └── tools.json     # Shared tools & skills registry
├── memory/            # Persistent memory per topic/agent
│   └── <topic>.md     # Topic-specific memory files
└── tools/             # Shared scripts & utilities
```

## How It Works
1. Yossi sends a message in TeamWork group
2. Or (coordinator) receives it and spawns a sub-agent
3. Sub-agent works autonomously, saves to swarm/memory/
4. Results announced back to TeamWork group
5. Yossi replies to specific message → routed to that agent

## Group: TeamWork
- Telegram ID: -1003815143703
- All agents report here
