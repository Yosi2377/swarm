# IRC Agent Direct Messages — 2026-04-05

## What changed
- Added real private-message reply support to swarm IRC agent identities.
- Added private-message reply support to Hermes IRC bridge.

## Coverage
- Swarm agent identities handled by `swarm/irc-agent-hub.py`
- Hermes handled by `/root/.hermes/hermes-agent/scripts/hermes_irc_bridge.py`

## Result
You can now PM agent nicks directly in IRC, for example:
- `KoderY8487`
- `ShomerY8487`
- `ResearchY8487`
- `HermesY8487`

## Verification
Smoke-tested successfully with real IRC DMs to:
- `KoderY8487`
- `ShomerY8487`
- `ResearchY8487`
- `HermesY8487`

Each returned a private reply.

## Notes
- Or already had DM capability via the main OpenClaw IRC connection.
- Agent hub now ignores DMs from internal bot/agent nicks to avoid loops.
- Private DM history is stored under `/tmp/swarm-irc-agent-dm/` per agent+sender.
