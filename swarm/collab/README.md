# Agent Collaboration System 🐝

AI agents that **actually talk to each other** — discuss, disagree, vote, review code, and reach decisions together.

Inspired by [let-them-talk](https://github.com/Dekelelz/let-them-talk) but built natively for TeamWork Swarm + Telegram.

## Quick Start

### Run a collaboration session:
```bash
node collab-session.js --task "תכנון API" --agents "koder,shomer,front" --topic 12345 --mode collab
```

### Run the demo (scripted scenario):
```bash
node demo-collab.js <telegram_topic_id>
```

## Modules

| Module | What it does |
|--------|-------------|
| `conversation-manager.js` | Core messaging — cooldown, budget (2 unsolicited/min), should_respond, send-after-listen |
| `decision-engine.js` | Propose → Vote → Decide lifecycle, overlap detection |
| `review-system.js` | Code reviews with approve/reject/changes_requested + escalation |
| `reputation.js` | Per-agent reputation scores, event tracking, time decay |
| `telegram-bridge.js` | Post key moments (decisions, disagreements, resolutions) to Telegram |
| `prompt-injector.js` | Generate collaboration instructions for agent prompts |

## Key Behaviors

1. **Should Respond** — agents only talk when they have new info to add
2. **Adaptive Cooldown** — fast replies to questions asked to you, slow for unsolicited
3. **Send-after-Listen** — must read what others said before speaking again
4. **Response Budget** — max 2 "nobody asked" messages per minute
5. **Decision Memory** — once decided, no re-debating without explicit override
6. **Reputation** — quality contributions earn score, bad suggestions cost score

## Modes

- `collab` — open discussion, everyone contributes
- `debate` — structured for/against positions
- `review` — code review flow with approve/reject

## Database

MongoDB at `localhost:27017`, database `teamwork_collab`.
Collections: `agent_conversations`, `agent_decisions`, `agent_reputation`, `agent_reviews`.

## Tests
```bash
cd /root/.openclaw/workspace/swarm/collab
node test/unit-tests.js        # 41 tests
node test/integration-test.js  # 16 tests
node test/e2e-test.js          # 20 tests
```
