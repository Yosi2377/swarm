# Texas Poker Game Setup - 2026-02-09

## Repository
- Source: https://github.com/wzdwc/TexasPokerGame
- Local: /root/TexasPokerGame

## Stack
- **Server**: Midway.js 1.x + Egg.js + Socket.io + MySQL + Redis
- **Client**: Vue 2 + TypeScript + Socket.io-client

## Running
- Server: `cd /root/TexasPokerGame/server && npx cross-env NODE_ENV=local midway-bin dev --ts --framework=midway`
- Port: 7001
- Client built at: /root/TexasPokerGame/client/dist (served via /public/)

## DB
- MySQL: localhost:27017, DB: poker, user: root (no password, mysql_native_password)
- Redis: localhost:6379, password: 123456

## Fixes Applied
1. Created missing `app/service`, `app/middleware`, `app/io/middleware` dirs in node_modules packages
2. Created `/root/TexasPokerGame/server/config/config.default.js` with keys + csrf disabled
3. Changed MySQL root auth to mysql_native_password
4. Updated client origin.ts to use 95.111.247.22 for production

## API Endpoints
- POST /node/user/register {userAccount, password, nickName}
- POST /node/user/login {userAccount, password}
- Socket.io namespace: /socket (game actions)

## URLs
- API: http://95.111.247.22:7001
- Client: http://95.111.247.22:7001/public/index.html
