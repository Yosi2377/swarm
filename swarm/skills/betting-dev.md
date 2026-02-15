# Skill: ZozoBet Development

## Project Overview
ZozoBet — אתר הימורי ספורט עם odds בזמן אמת, multi-bet, cashout, settlement engine.

## Architecture
- **Domain**: zozobet.duckdns.org
- **Stack**: Node.js + Express + MongoDB + Redis + Nginx
- **Production**: `/root/BettingPlatform` (ports: 3001 backend, 3002 aggregator, 8089 nginx)
- **Sandbox**: `/root/sandbox/BettingPlatform` (ports: 9301 backend, 9302 aggregator, 9089 nginx)
- **DB**: MongoDB `mongodb://localhost:27017/betting` (shared between sandbox/production!)
- **Services**: `betting-backend`, `betting-aggregator`, `sandbox-betting-backend`, `sandbox-betting-aggregator`

## Key Files
| File | Purpose |
|------|---------|
| `backend/src/index.js` | Express server, socket.io, middleware |
| `backend/src/routes/events.js` | Events API, full-odds endpoint |
| `backend/src/routes/bets.js` | Bet placement, cashout |
| `backend/src/routes/admin.js` | Admin CRUD, transactions, user mgmt |
| `backend/src/routes/agent.js` | Agent panel routes |
| `backend/src/routes/superagent.js` | Super Agent routes |
| `backend/src/engines/settlement.js` | Bet settlement (h2h, totals, spreads, void) |
| `backend/src/models/` | User, Bet, Event, Transaction, Settings |
| `backend/public/index.html` | Main frontend (sports, live, bets, modal) |
| `backend/public/live.html` | Live-only page |
| `backend/public/admin.html` | Admin panel |
| `backend/public/agent.html` | Agent panel |
| `backend/public/superagent.html` | Super Agent panel |
| `aggregator/src/index.js` | Event sync, basic odds, live scores |
| `aggregator/src/betsapi.js` | BetsAPI class + odds parser |
| `aggregator/src/inplay-parser.js` | Live inplay odds parser (bet365 raw format) |

## APIs
- **BetsAPI** (primary): Token `246040-qAUnad5f8My9aG`, 3600 req/hour
  - `v1/bet365/upcoming?sport_id={id}` — upcoming events
  - `v3/bet365/prematch?FI={eventId}` — full odds per event
  - `v1/bet365/inplay?sport_id={id}` — live events + scores + odds (raw bet365 format)
- **The Odds API** (backup): Key `7fe09240c22a6c2440e25f0ae9955138`, 100K credits/month
- **Sport IDs**: 1=soccer, 18=basketball, 13=tennis

## Role Hierarchy
Admin > Super Agent > Agent > Player
- Admin: full access
- Super Agent: manages agents under them
- Agent: manages players, can't bet
- Player: can bet

## Auth
- JWT with httpOnly cookies (7 day expiry)
- Admin user: zozo / 123456
- `app.set('trust proxy', 1)` required for express-rate-limit

## Key Patterns
- Event IDs: `b365_` prefix (e.g., `b365_189734185`)
- On-demand odds: Table shows basic h2h, clicking match fetches all 14+ markets
- 10-sec DB cache on `fullOddsFetched` timestamp
- Auto-refresh: modal every 5sec, table every 10sec
- BLOCKED_LEAGUES regex filters esports/simulations
- No-cache headers on static files

## Rules
1. ⛔ ALWAYS work in sandbox first (`/root/sandbox/BettingPlatform`)
2. ⛔ NEVER push to production without explicit user approval
3. 📸 ALWAYS send screenshots as proof before marking done
4. 🔧 Use `systemctl restart sandbox-betting-backend` to apply changes
5. Git commit after every change
6. Test with Puppeteer: `/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome`
