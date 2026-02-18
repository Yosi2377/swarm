---
name: betting-platform
description: ZozoBet sports betting platform knowledge base. Architecture, API integration (BetsAPI), odds parsing, market types, deployment pipeline. Use when working on betting platform code, fixing odds issues, adding markets, or deploying changes.
---

# ZozoBet Betting Platform

## Architecture

| Component | Path | Port | Service |
|-----------|------|------|---------|
| Backend | `/root/BettingPlatform/backend` | 3001 | betting-backend |
| Aggregator | `/root/BettingPlatform/aggregator` | — | betting-aggregator |
| Sandbox | `/root/sandbox/BettingPlatform` | 9301 | sandbox-betting-backend |
| Nginx | — | 8089→3001, 9089→9301 | nginx |

## Key Files

| File | Purpose |
|------|---------|
| `aggregator/src/index.js` | Main aggregator: syncLiveScores (15s), syncBasicOdds (60s), syncLiveEventOdds (45s) |
| `aggregator/src/inplay-parser.js` | Parse BetsAPI inplay feed → h2h odds, scores, time |
| `aggregator/src/betsapi.js` | BetsAPI client with rate limiting |
| `backend/src/routes/events.js` | Event API + full-odds popup endpoint |
| `backend/public/index.html` | Main frontend (single file, ~6000 lines) |
| `backend/public/admin.html` | Admin panel |

## BetsAPI Integration

- **Token**: In `.env` as `BETSAPI_TOKEN`
- **Budget**: 3,600 credits/hour shared across all calls
- **Inplay feed**: `/v3/bet365/inplay_filter` — scores, time, h2h odds
- **Prematch odds**: `/v2/event/odds/summary` — all markets
- **Live event**: `/v3/bet365/event?FI={id}` — full market detail (DC, O/U, BTTS etc.)

## Market Types (21 found)

Fulltime Result, Double Chance, Draw No Bet, Both Teams to Score, Match Goals, Alternative Match Goals, Goal Line, Asian Handicap, 3-Way Handicap, Final Score, Goals Odd/Even, 2nd Goal, Last Team to Score, Either to Score, Multi Scorers, Match Corners, 2-Way Corners, Asian Corners, Corners, 2nd Half Corners, Corners Race, Goalscorers

## Critical Lessons

1. **Prematch must not overwrite inplay odds** — `syncBasicOdds()` skips `liveProtectedMarkets` for live events
2. **2-way vs 3-way sports** — Tennis has 2 PAs (home/away), Football has 3 (home/draw/away). Check `_h2hPaCount`
3. **Live sync intervals**: inplay 15s, liveEventOdds 45s, prematch 60s rotation (25 events/cycle)
4. **Redis cache 5s TTL** — near-realtime frontend updates
5. **Production files have chattr +i** — must unlock before deploy

## CSS Selectors (Frontend)

| Selector | Element |
|----------|---------|
| `.c-match` | Match row |
| `.c-odds` | Odds cell |
| `.c-time` | Time cell |
| `.b365-btn` | Odds button (popup) |
| `.b365-row` | Market row (popup) |
| `.b365-section` | Market section |
| `.auth-wrap` | Login form |
| `.bal` | Balance display |

## Deploy Pipeline

1. Work in sandbox (`/root/sandbox/BettingPlatform`)
2. Test with `evaluator.sh betting <thread>`
3. Get Yossi's approval
4. Run `deploy.sh` (handles chattr -i/+i automatically)
