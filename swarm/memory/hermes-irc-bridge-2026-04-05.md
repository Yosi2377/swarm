# Hermes IRC Bridge — 2026-04-05

## What was added
- Hermes connected to the private TeamWork IRC server via a dedicated bridge service
- Nick: `HermesY8487`
- Service: `systemctl --user status hermes-irc-bridge.service`
- Script: `/root/.hermes/hermes-agent/scripts/hermes_irc_bridge.py`

## Policy
- `#myops` → mention-only
- `#agent-chat` → consult / review mode
- `#job-*` → mention / on-demand review

## Hermes-side changes
- Added `irc` platform hint in `agent/prompt_builder.py`
- Added `irc` platform mapping in `hermes_cli/tools_config.py`
- Hermes repo commit: `f70f9b82` — `Add Hermes IRC bridge for TeamWork channels`

## Local config / service
- `.env` updated with `HERMES_IRC_*` variables under `/root/.hermes/.env`
- systemd user unit: `/root/.config/systemd/user/hermes-irc-bridge.service`

## Verification
- `HermesY8487` visible in `#myops`
- `HermesY8487` visible in `#agent-chat`
- Mention smoke test succeeded in `#agent-chat`

## Notes
- Hermes does NOT have native IRC gateway support yet; this bridge is the integration layer.
- Bridge auto-joins known `#job-*` channels by reading swarm job metadata.
