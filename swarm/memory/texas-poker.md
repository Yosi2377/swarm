# Texas Poker Game - Installation Log

## Task
Install and setup Texas Hold'em Poker multiplayer game from https://github.com/wzdwc/TexasPokerGame

## Progress
- ✅ Cloned repo to `/root/TexasPokerGame/`
- ✅ Server dependencies installed (844 packages) — npm, not yarn (yarn SSL cert expired)
- ✅ Client dependencies installed (Vue.js + Socket.IO)
- ✅ MySQL database "poker" created with schema from `database/*.sql`
- ✅ Redis active (password: 123456)
- ✅ Created missing `app/schedule`, `app/service` etc. dirs (egg.js bug with missing dirs)
- ✅ Server runs on port 7001 (Egg.js + Midway framework)

## Architecture
- **Server**: Egg.js + Midway (TypeScript), port 7001
- **Client**: Vue.js (vue-cli-service)
- **DB**: MySQL (root, no password, database: poker)
- **Cache**: Redis (password: 123456)
- **Config**: `server/src/config/config.default.ts`

## How to Start
```bash
# Server
cd /root/TexasPokerGame/server
NODE_ENV=local nohup npx midway-bin dev --ts > /tmp/poker-server.log 2>&1 &

# Client (needs build or dev mode)
cd /root/TexasPokerGame/client
npm run serve  # dev mode on port 8080
# or
npm run build  # build to dist/
```

## Known Issues
- yarn fails with SSL cert expired — use npm instead
- egg.js requires empty `app/schedule` dirs in various node_modules — created manually
- `midway` module not found warning (non-fatal)
- Server returns 500 on root `/` (needs proper routing)

## Next Steps
- [ ] Build client (`npm run build`)
- [ ] Configure nginx proxy for poker (port 7002 or similar)
- [ ] Test the full game flow
- [ ] Set up systemd service for auto-start
