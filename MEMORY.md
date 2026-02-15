# MEMORY.md - Long-Term Memory

## About Yossi (יוסי)
- Hebrew speaker, communicates primarily in Hebrew
- Telegram ID: 8487535487
- Unity account: Yosi2377@gmail.com / yosi2377
- Timezone: Europe/Berlin (GMT+1)
- Named me אור (Or) - "Light" in Hebrew on 2026-02-02

## Projects Overview - IMPORTANT!
| Project | Folder | Domain | Ports | Services |
|---------|--------|--------|-------|----------|
| **פוקר (Texas Poker)** | `/root/TexasPokerGame` | `zozopoker.duckdns.org` | 8088 (client) + 7001 (server) | texas-poker, poker-client, poker-admin |
| **בלאקג'ק (Blackjack)** | `/root/Blackjack-Game-Multiplayer` | `95.111.247.22:3000` | 3000 | blackjack |

| **הימורים (BetPro)** | `/root/BettingPlatform` | `95.111.247.22:8089` | 8089 (nginx) → 3001 (backend) + 3002 (aggregator) | betting-backend, betting-aggregator |

⚠️ When Yossi says "פוקר" = TexasPokerGame. When he says "בלאקג'ק" = Blackjack-Game-Multiplayer. When he says "הימורים"/"בטים" = BettingPlatform. Don't mix them up!

## Current Project: Multiplayer Blackjack Game
**Started**: 2026-02-06
**Reference**: https://playmexstudios.itch.io/multiplayer-blackjack-game
**Goal**: Professional casino-style multiplayer blackjack with auth, admin, AI assets

### Architecture (Current - HTML/JS/WebSocket)
- **Path**: `/root/Blackjack-Game-Multiplayer`
- **Stack**: Node.js + Express + WebSocket + MongoDB
- **Port**: 3000 (systemd service `blackjack`)
- **URL**: http://95.111.247.22:3000

### Key Files
| File | Lines | Purpose |
|------|-------|---------|
| `index.js` | 594 | WebSocket server, game logic, rooms |
| `public/js/client.js` | 1541 | WebSocket client, game UI interaction |
| `public/js/app.js` | 1368 | UI logic, betting, buttons, lobby |
| `public/js/animations.js` | 182 | GSAP card/chip animations |
| `public/index.html` | 564 | Game page with lobby |
| `public/login.html` | - | Player login page |
| `public/admin/dashboard.html` | - | Admin panel |

### Features Working
- WebSocket multiplayer (rooms, join/create)
- MongoDB auth (JWT, httpOnly cookies)
- Admin panel (CRUD users, stats, game history)
- SVG card assets, GSAP animations
- Sound effects (deal, chip, win/lose, timer)
- Lobby with room list (auto-refresh 3s)
- Mobile responsive (scaling, hidden HOW TO PLAY)
- systemd service (auto-start)
- Admin-only room/user creation

### Auth
- Default admin: admin/admin123
- MongoDB: localhost:27017/blackjack
- JWT with httpOnly cookies (7 day expiry)

### Previous Unity WebGL Attempt
- Path: `/root/UnityProjects/MultiplayerBlackjack`
- Abandoned due to WebGL shader issues on headless VPS
- 37 builds, custom SimpleColor shader eventually worked
- Switched to HTML/JS approach instead

## VPS Access
- **IP**: 95.111.247.22
- **VNC**: :5901 (password: desktop1)
- **HTTP**: :8080 (game server)
- **Unity**: `/root/Unity/Hub/Editor/6000.0.67f1/Editor/Unity`

## API Keys
- **Gemini API**: configured in openclaw.json under skills.entries.nano-banana-pro.apiKey
- Used for Imagen 4.0 and Nano Banana Pro image generation

## Lessons Learned
- Unity Hub GUI doesn't work on headless VPS - use Licensing Client CLI
- `[RuntimeInitializeOnLoadMethod]` is key for procedural scene creation without editor
- Standard Shader is unreliable in WebGL - need alternative approach
- Always use ShaderHelper.CreateMaterial() instead of raw Shader.Find()
- Firefox on VNC can crash - restart with fresh profile when stuck
- BetsAPI inplay returns ALL sports in one call (sport_id param ignored)
- Events filter must be 12h+ not 3h — matches last longer than 3h window
- ALWAYS create topic + sandbox + screenshots + approval before production
- NEVER code directly as orchestrator — delegate to koder
- Agent skills system: swarm/skills/ for project knowledge, swarm/tasks/ for task files
- Learning system: swarm/learn.sh for lessons, scores, auto-skill evolution
