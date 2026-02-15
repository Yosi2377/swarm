# ZozoBet — מבנה DB + API

## MongoDB Collections

### users
```
{
  _id: ObjectId,
  username: String,
  password: String (hashed),
  role: "admin" | "superagent" | "agent" | "player",
  parentId: ObjectId (for agents/players — who manages them),
  balance: Number,
  status: "active" | "blocked",
  createdAt: Date
}
```

### bets
```
{
  _id: ObjectId,
  user: ObjectId (→ users._id),     ⚠️ NOT userId! Field name is "user"
  eventId: String (e.g. "b365_123"),
  eventName: String,
  market: String,
  selection: String,
  odds: Number,
  amount: Number,
  status: "open" | "won" | "lost" | "void" | "cashout",
  potentialWin: Number,
  periodId: ObjectId (→ periods._id),
  createdAt: Date,
  settledAt: Date
}
```
P&L calculation:
- won: `amount * odds - amount`
- lost: `-amount`
- void: `0` (refunded)
- open: `0` (pending)
- cashout: `cashoutAmount - amount`

### events
```
{
  _id: ObjectId,
  betsapiId: String,
  eventId: String (prefixed "b365_"),
  sport: "soccer" | "basketball" | "tennis",
  league: String,
  home: String,
  away: String,
  commenceTime: Date,
  scores: { home: Number, away: Number },
  matchMinute: String,
  matchPeriod: String,
  status: "upcoming" | "live" | "completed",
  odds: Object (markets data),
  fullOdds: Object (detailed markets),
  updatedAt: Date
}
```

### transactions
```
{
  _id: ObjectId,
  user: ObjectId (→ users._id),     ⚠️ NOT userId!
  type: "deposit" | "withdrawal" | "bet" | "win" | "refund" | "admin_edit",
  amount: Number,
  balanceBefore: Number,
  balanceAfter: Number,
  description: String,
  createdAt: Date
}
```

### periods
```
{
  _id: ObjectId,
  name: String,
  startDate: Date,
  endDate: Date,
  status: "active" | "closed",
  createdAt: Date
}
```

## API Routes

### Auth
- POST /api/auth/login → {token, user}
- POST /api/auth/register → {token, user}

### Events
- GET /api/events → all events (filtered: live + upcoming 3h)
- GET /api/events?live=true → only live events
- GET /api/full-odds/:eventId → detailed odds for event

### Bets
- POST /api/bets → place bet {eventId, market, selection, odds, amount}
- GET /api/bets → user's bets
- GET /api/bets?all=true → admin: all bets
- GET /api/bets/hierarchy → admin: bets grouped by superagent→agent→player
- PUT /api/bets/:id → admin: edit bet {status, amount}
- POST /api/bets/:id/void → admin: void bet (refunds balance)

### Admin
- GET /api/admin/users → all users
- POST /api/admin/users → create user
- PUT /api/admin/users/:id → edit user
- POST /api/admin/impersonate/:id → login as user
- POST /api/admin/return-to-admin → return from impersonation
- POST /api/admin/reset-period → close current period

## File Structure
```
/root/BettingPlatform/
  backend/
    src/
      server.js (or index.js)
      config/db.js
      models/ (User.js, Bet.js, Event.js, Transaction.js, Period.js)
      routes/ (auth.js, bets.js, events.js, admin.js)
      engines/settlement.js
    public/
      index.html (main betting page)
      live.html (live events page)
      admin.html (admin panel)
  aggregator/
    src/
      index.js (main sync loop)
      betsapi.js (BetsAPI client)
      inplay-parser.js (live scores/odds parser)
```

## Sandbox
- Path: /root/sandbox/BettingPlatform
- DB: betting_sandbox
- Backend port: 9301
- Nginx port: 9089
- ⛔ Aggregator BLOCKED (use production data via sync)

## Common Mistakes
- ❌ Using `userId` → ✅ Use `user` (field name in bets/transactions)
- ❌ Editing production directly → ✅ Always sandbox first
- ❌ Starting sandbox-aggregator → ✅ It's blocked, don't try
- ❌ commenceTime as string → ✅ Must be Date object for $gte queries
