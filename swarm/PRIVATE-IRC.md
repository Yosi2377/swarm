# Private IRC (TeamWork)

## Server
- Daemon: ngIRCd
- Host: `95.111.247.22`
- Port: `6667`
- Network: `TeamWork`
- Server name: `irc.teamwork.local`

## Channels
- `#myops` — main ops channel
- `#agent-chat` — internal agent coordination channel
- `#job-*` — dynamic job channels added on demand

## OpenClaw IRC mode
- OpenClaw now points to the private IRC server on `127.0.0.1:6667`
- Each agent is connected as its own IRC account/nick
- `send.sh` sends via `--account <agent>` so visible sender identity matches the agent
- `irc-ensure-account-channel.py` auto-adds dynamic channels for the specific agent account

## Current visible agent nicks
- `OrYossiOps8487`
- `KoderY8487`
- `WorkerY8487`
- `ShomerY8487`
- `TzayarY8487`
- `ResearchY8487`
- `BodekY8487`
- `DataY8487`
- `DebugY8487`
- `DockerY8487`
- `FrontY8487`
- `BackY8487`
- `TesterY8487`
- `RefactorY8487`
- `MonitorY8487`
- `OptimizeY8487`
- `IntegrateY8487`

## Notes
- Previous Libera/ZNC config was backed up before switching
- ngIRCd is currently plaintext on port 6667 (no TLS yet)
- If needed later: add TLS or firewall restrictions
