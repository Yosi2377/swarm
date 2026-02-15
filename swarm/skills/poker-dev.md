# Skill: Texas Poker Development

## Project Overview
Texas Poker — משחק פוקר מרובה שחקנים עם לובי, חדרים, admin panel.

## Architecture
- **Domain**: zozopoker.duckdns.org
- **Stack**: Midway.js (TypeScript) + Socket.IO + EJS templates
- **Production**: `/root/TexasPokerGame` (ports: 7001 server, 8088 client via nginx)
- **Sandbox**: `/root/sandbox/TexasPokerGame` (ports: 9001 server, 9088 client)
- **Services**: `texas-poker` (server), `poker-client` (client), `poker-admin` (admin)

## Key Directories
| Path | Purpose |
|------|---------|
| `game-server/src/` | Game logic, socket handlers |
| `game-client/src/` | Client UI, EJS templates |
| `admin-server/` | Admin panel |
| `game-server/src/service/` | Game services (room, player, deck) |
| `game-client/src/views/` | EJS templates |

## Auth
- Admin: zozo / 123456

## Rules
1. ⛔ ALWAYS work in sandbox (`/root/sandbox/TexasPokerGame`)
2. ⛔ NEVER push to production without user approval
3. 📸 Screenshots required before marking done
4. Git commit after every change
