# Hermes IRC fallback fix — 2026-04-20

## Symptom
- `HermesY8487` was connected and visible in IRC
- But DMs and channel mentions returned no reply
- `hermes-irc-bridge.service` logs showed:
  - `Invalid API response`
  - `response.output is empty`
  - on the native Hermes AIAgent path using Codex backend models

## Root cause
Hermes native response path was producing empty `final_response` values on IRC prompts.
The IRC bridge treated that as silence, so Hermes looked online but non-responsive.

## Fix
Added a bridge-level fallback in `/root/.hermes/hermes-agent/scripts/hermes_irc_bridge.py`:
- First try native Hermes AIAgent as before
- If `final_response` is empty or the native path throws, automatically fall back to `codex exec`
- Fallback uses a persistent scratch git repo under `/tmp/hermes-irc-codex`
- Returns only plain-text IRC body, preserving Hermes IRC policy prompt/history

## Verification
PASS after restart:
- DM to `HermesY8487` from authenticated `Yossi` => `ok`
- Mention in `#agent-chat` => `ok`

## Notes
This keeps Hermes native path intact when it works, but prevents silent failure on IRC when it returns empty output.
