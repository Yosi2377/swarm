# Ergo Parallel Migration — 2026-04-05

## What changed
- Installed Ergo IRC server v2.18.0 in parallel to ngIRCd
- Running on `127.0.0.1:16669`
- Service: `systemctl --user status ergo-teamwork.service`

## Accounts registered
- `Yossi`
- `OrYossiOps8487`
- `HermesY8487`
- all swarm agent nicks from `swarm/irc-agent-accounts.json`

## Auth model
- Ergo built-in accounts / NickServ available
- The Lounge configured for SASL plain as `Yossi`
- OpenClaw main IRC switched to Ergo with PASS `account:password`
- Swarm agent hub switched to Ergo with PASS `account:password`
- Hermes IRC bridge switched to Ergo with PASS `account:password`

## DM / identity result
- `Or` DM now works again on Ergo
- Verified from authenticated `Yossi` account:
  - `PRIVMSG OrYossiOps8487 ...` => reply `ok`
- Verified visible presence in `#myops` and `#agent-chat` for:
  - Or
  - Hermes
  - all agent nicks

## Important config state
- `openclaw.json` IRC points to `127.0.0.1:16669`
- DM auth for Or now uses authenticated `Yossi` hostmask on Ergo (stable cloak), not raw changing public IP
- `thelounge/config.js` defaults point to Ergo and SASL-login as `Yossi`

## Services affected
- `ergo-teamwork.service`
- `openclaw-gateway.service`
- `swarm-irc-agent-hub.service`
- `hermes-irc-bridge.service`
- `thelounge-teamwork.service`

## Verification summary
PASS:
- Ergo service active
- OpenClaw IRC provider active on Ergo
- Agent hub active on Ergo
- Hermes bridge active on Ergo
- NAMES on `#myops` and `#agent-chat` shows Or + Hermes + all agents
- DM to `OrYossiOps8487` from authenticated `Yossi` works
