# Poker Lobby Real-Time Update (2026-02-11)

## What Was Done
Converted the poker lobby from HTTP polling (every 5s) to Socket.IO real-time updates.

## Files Modified

### Server
- `server/src/app/io/controller/nsp.ts` - Added `joinLobby`, `leaveLobby`, `broadcastLobbyUpdate` static method
- `server/src/app/io/middleware/auth.ts` - Skip room check for `__lobby__` connections
- `server/src/app/io/middleware/join.ts` - Skip game room setup for `__lobby__`, broadcast lobby on player join
- `server/src/app/router.ts` - Added `joinLobby`/`leaveLobby` routes
- `server/src/lib/baseSocketController.ts` - Added `broadcastLobbyUpdate()` helper
- `server/src/app/io/controller/game.ts` - Added lobby broadcasts on: buyIn, sitDown, standUp, playGame, gameOver
- `server/src/app/controller/room.ts` - Added lobby broadcasts on: room create, room delete
- `server/tsconfig.json` - Added `noEmitOnError: false`, `skipLibCheck: true`

### Client
- `client/src/views/home.vue` - Socket.IO connection to `__lobby__` room, listens for `lobbyUpdate` events, fallback polling 30s

## How It Works
- Lobby clients connect to `/socket` namespace with `room=__lobby__`
- Server emits `lobbyUpdate` with full room list whenever rooms change
- Client updates immediately without page refresh
