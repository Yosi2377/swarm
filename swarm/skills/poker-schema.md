# Texas Poker — מבנה DB + API

## Database: MySQL (`poker`)

⚠️ **NOT MongoDB!** This project uses MySQL with `mysql2` driver.

### Tables

#### user
```sql
id          INT AUTO_INCREMENT PRIMARY KEY
nickName    CHAR(25)
password    CHAR(25)          -- plain text!
account     CHAR(25)          -- username
role        VARCHAR(10)       -- 'admin' | 'agent' | 'player' (default: 'player')
balance     INT               -- credits (default: 0)
createdBy   INT               -- parent agent/admin ID
isOnline    TINYINT           -- 0/1
lastLogin   DATETIME
create_time TIMESTAMP
update_time DATETIME
```

#### game
```sql
id          INT AUTO_INCREMENT PRIMARY KEY
roomNumber  INT
status      INT               -- game status code
commonCard  TEXT              -- community cards JSON
winners     TEXT (utf8)       -- winners JSON
pot         DECIMAL(8,0)
create_time TIMESTAMP
update_time DATETIME
```

#### player (game participation)
```sql
id          INT AUTO_INCREMENT PRIMARY KEY
gameId      INT               -- → game.id
roomNumber  INT
buyIn       INT NOT NULL
handCard    VARCHAR(25)       -- player's hole cards
counter     INT               -- chip count
userId      INT               -- → user.id (indexed)
create_time TIMESTAMP
update_time DATETIME
```

#### command_record (game actions log)
```sql
id          INT AUTO_INCREMENT PRIMARY KEY
userId      INT (indexed)     -- → user.id
gameId      INT (indexed)     -- → game.id
type        TEXT              -- action type
gameStatus  INT
counter     INT
command     TEXT              -- action details
commonCard  TEXT
pot         INT
roomNumber  INT
create_time TIMESTAMP
update_time DATETIME
```

#### transaction_log (credits movement)
```sql
id                  INT AUTO_INCREMENT PRIMARY KEY
userId              INT NOT NULL (indexed)
username            VARCHAR(25) NOT NULL
type                ENUM('deposit','withdraw','win','loss','commission')
amount              INT NOT NULL
balanceBefore       INT NOT NULL
balanceAfter        INT NOT NULL
performedBy         INT (indexed)    -- who did it
performedByUsername  VARCHAR(25)
note                VARCHAR(255)
create_time         TIMESTAMP (indexed)
```

#### settings (key-value config)
```sql
skey        VARCHAR(50) PRIMARY KEY
svalue      VARCHAR(255)
updated_at  TIMESTAMP
```
Known keys: `commissionRate` (0-100, default 10)

## Architecture

### Game Server (Midway.js + Socket.IO)
- **Framework**: Midway.js (Egg.js based) — TypeScript
- **Port**: 7001 (default Midway)
- **DB**: MySQL via `egg-mysql` plugin
- **Cache**: Redis (127.0.0.1:6379, password: `123456`)
- **JWT Secret**: `123456`
- **Socket.IO namespace**: `/socket`

### Admin/Agent Server (Express)
- **File**: `admin-server.js`
- **Port**: 7002
- **DB**: MySQL via `mysql2/promise` pool
- **JWT Secret**: `poker-admin-secret-2026`
- **Static**: `/admin-public/`

## Socket.IO Events (Game)
| Event | Handler | Description |
|-------|---------|-------------|
| `exchange` | nsp.exchange | General message exchange |
| `broadcast` | nsp.broadcast | Broadcast to room |
| `buyIn` | game.buyIn | Buy into table |
| `playGame` | game.playGame | Start game |
| `action` | game.action | Player action (fold/call/raise) |
| `sitDown` | game.sitDown | Take seat |
| `standUp` | game.standUp | Leave seat |
| `delayTime` | game.delayTime | Request extra time |
| `joinLobby` | nsp.joinLobby | Enter lobby |
| `leaveLobby` | nsp.leaveLobby | Leave lobby |

## Admin API Routes (port 7002)

### Auth
- POST `/api/login` → {username, password, panel}
- GET `/api/me` → current user
- POST `/api/logout`

### Admin Panel
- GET `/api/admin/stats` → dashboard stats
- GET `/api/admin/users` → all users with creator info
- POST `/api/admin/users` → create user {username, password, nickName, role, balance}
- PUT `/api/admin/users/:id` → update {password, role, balance}
- DELETE `/api/admin/users/:id` → delete user (cascades agent's players)
- POST `/api/admin/users/:id/credit` → add credits {amount}
- POST `/api/admin/users/:id/withdraw` → remove credits {amount}
- GET `/api/admin/users/:id/details` → user + win/loss stats
- GET `/api/admin/transactions` → paginated (?page, ?limit, ?type, ?userId)
- GET `/api/admin/games` → paginated game history
- GET/PUT `/api/admin/settings/commission` → commission rate

### Agent Panel
- GET `/api/agent/stats` → agent dashboard
- GET `/api/agent/users` → agent's players
- POST `/api/agent/users` → create player (deducts from agent balance)
- PUT `/api/agent/users/:id` → update player password
- DELETE `/api/agent/users/:id` → delete player
- POST `/api/agent/users/:id/credit` → credit player (from agent balance)
- POST `/api/agent/users/:id/withdraw` → withdraw from player (to agent balance)
- GET `/api/agent/transactions` → agent + players transactions

### Pages
- `/admin` → admin dashboard (requires admin role)
- `/admin/login` → admin login (supports auto-login via game JWT)
- `/agent` → agent dashboard
- `/agent/login` → agent login

## File Structure
```
/root/TexasPokerGame/
  package.json              -- deps: express, mysql2, jsonwebtoken, cookie-parser
  admin-server.js           -- Admin/Agent panel (port 7002)
  admin-public/             -- Admin panel HTML files
    admin-dashboard.html
    admin-login.html
    agent-dashboard.html
    agent-login.html
  database/
    poker.sql               -- Original schema (basic tables only)
  server/                   -- Game server (Midway.js/TypeScript)
    src/
      app.ts                -- App entry
      app/
        router.ts           -- Socket.IO routes
        controller/         -- HTTP controllers
          account.ts        -- Login/register
          user.ts           -- User CRUD
          room.ts           -- Room management
          gameRecord.ts     -- Game history
        core/               -- Game engine
          Poker.ts          -- Card deck/evaluation
          PokerGame.ts      -- Game flow logic
          PokerStyle.ts     -- Hand ranking
          Player.ts         -- Player state
        io/
          controller/
            nsp.ts          -- Socket namespace handlers
            game.ts         -- Game socket handlers
          middleware/
            auth.ts         -- Socket auth
            join.ts         -- Join room
            leave.ts        -- Leave room
      service/              -- Business logic
        account.ts, user.ts, room.ts, game.ts, player.ts, commandRecord.ts
      config/
        config.default.ts   -- MySQL, Redis, JWT config
        plugin.ts           -- Egg plugins
      interface/            -- TypeScript interfaces
      lib/                  -- Base classes
  client/                   -- Vue.js frontend
    src/
      main.ts
      router/index.ts
      store/index.ts
      service/index.ts
      interface/            -- Shared interfaces
      utils/                -- Helpers (request, cards, etc.)
```

## Sandbox
- Path: `/root/sandbox/TexasPokerGame`
- Same structure as production

## Role Hierarchy
Admin > Agent > Player
- **Admin**: full access to all users, games, transactions, settings
- **Agent**: manages own players, credits flow through agent balance
- **Player**: plays poker

## Common Mistakes
- ❌ Looking for MongoDB/Mongoose → ✅ This project uses **MySQL** (`mysql2`)
- ❌ Using `userId` field in user table → ✅ It's just `id`
- ❌ Confusing the two servers → ✅ Game: port 7001 (Midway), Admin: port 7002 (Express)
- ❌ Confusing JWT secrets → ✅ Game: `123456`, Admin: `poker-admin-secret-2026`
- ❌ Assuming hashed passwords → ✅ Passwords stored **plain text** in `user.password`
- ❌ Editing production directly → ✅ Always sandbox first
