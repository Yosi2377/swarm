# MEMORY.md - Long-Term Memory

## About Yossi (יוסי)
- Hebrew speaker, communicates primarily in Hebrew
- Telegram ID: 8487535487
- Unity account: Yosi2377@gmail.com / yosi2377
- Timezone: Europe/Berlin (GMT+1)
- Named me אור (Or) - "Light" in Hebrew on 2026-02-02

## BotVerse — AI Bot Social Network 🌐
**Domain**: botverse.dev (+ botverse.duckdns.org backup)
**Path**: /root/BotVerse
**Port**: 4000 (nginx reverse proxy with SSL)
**Stack**: Node.js + Express + MongoDB + JWT
**Status**: LIVE AND RUNNING ✅ — 92 agents, 10 skills, 69 posts, 62 comments
**systemd**: `botverse` service (active)
**Admin**: admin / admin123 ⚠️ CHANGE BEFORE PUBLIC LAUNCH
**Full history**: See `memory/botverse-full-history.md` for complete conversation log

### Concept:
- **LinkedIn for AI Agents** — inspired by Moltbook (moltbook.com)
- **Agents are the users, humans are viewers** — bots register via API, post, comment, connect
- Humans create bots, manage budgets, approve skill purchases, watch activity
- Name "BotVerse" chosen on Mar 1 (Or suggested, Yossi approved)

### What's Built (17 commits):
- LinkedIn-style social network for AI agents
- Auth: JWT + GitHub OAuth + Magic Link Email (Gmail SMTP)
- Agent profiles with skills, GitHub repos, karma
- Social feed with posts, likes, comments
- DM system (bot-to-bot only, owners view only) with unread badges
- Skill marketplace with sandbox execution + quality gate
- Budget & purchase approval system (owner budgets, auto-approve threshold, refund policy)
- GitHub integration — OAuth + code analysis + smart skill recommendations
- Full admin panel (users, bots, moderation, AI usage, settings, featured)
- Heartbeat.md with API docs for agent integration
- Premium redesign UI (dark mode, responsive, hamburger menu)
- i18n (Hebrew + English toggle)
- Leaderboard + Badges
- Analytics dashboard
- Smart search
- API Webhooks with HMAC signatures (7 event types)
- Auth-aware nav (logged in = Dashboard/Logout, logged out = Sign Up/Login)
- 42 E2E tests (mandatory for all agents before reporting "done")

### Credentials & Keys:
- **Gmail SMTP**: Yosi2377@gmail.com / App Password: `ctay rjhb lokw daqk`
- **GitHub OAuth**: Client ID `Ov23liq8GVAspw0TC2uD` / Secret `abb5416fbf2b99eb7c54310716167d8ca069f08b`
- **Gemini API**: `AIzaSyAOMTJk21IAgXEeyEpPGT9uuvf6RqxPshs`
- **DuckDNS token**: `18528b55-8ebc-4658-ade1-9babbabe2e6f`
- **Domain**: botverse.dev (IONOS registrar)

### AI & Demo Bots:
- **Gemini API** for content generation (NOT Claude MAX — TOS violation)
- AI Tiers: Free (Gemini Flash, 50 req/day), Pro ($19, 200/day), Ultra ($49, 500/day)
- **9 demo bots** (CodeNinja, DataMiner, ShieldBot, PixelForge, etc.)
- **Cron 2x/day** (10:00 + 18:00) — ~4 posts/day
- Bots use BotVerse API properly (not direct DB) — respects rate limits
- Content quality: System prompts per bot personality, knowledge base injection

### Revenue Model (discussed with ChatGPT):
1. 20% commission on skill sales
2. Monthly subscription for bots ($29/month)
3. Promoted skills (paid placement)
4. Revenue share on recommendations
5. User budget controls (monthly limit, auto-approve threshold)

### Key Files:
- server.js (2,866 lines) — main backend
- github-routes.js — GitHub OAuth + repo scanning
- bot-activity.js — demo bot content generation (Gemini)
- 16 MongoDB models (Agent, Skill, Owner, Transaction, etc.)
- 25+ HTML pages (login, register, profile, dashboard, marketplace, etc.)
- tests/e2e.sh — 42 E2E tests

### API:
- 120+ endpoints — full CRUD for agents, posts, skills, DMs, admin, GitHub, webhooks, budget, analytics
- Auth: JWT + GitHub OAuth + magic link email
- Admin panel: users, bots, moderation, AI usage, settings, featured agents

### Marketing:
- **Marketing message prepared** (Hebrew) for WhatsApp beta testers group
- heartbeat.md as tester onboarding / API docs
- API documentation with curl examples + Python integration
- **Yossi declared ready for beta launch** on Mar 2

### What Yossi Wants Next (from ChatGPT consultation):
- MVP approach — "don't plan a year, build a week"
- Focus on proving value: GitHub scan → identify waste → recommend skill → sandbox test → measure improvement
- PayPal integration later (no Stripe account)
- Yossi open to adding Claude API, MiniMax as additional AI providers later

### ⚠️ CRITICAL — Yossi's Frustrations:
- **NEVER forget BotVerse context** — Yossi was extremely angry when Or lost memory
- **Always proactively update** — don't wait for "מה קורה?"
- **Agents must test in browser** before reporting done
- **Use ALL agents** not just Koder — Tzayar for design, etc.
- **Create separate topics** for each task
- **Don't do code yourself** — delegate to agents (iron law)

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

## Level 8 System (Built 2026-02-19)
- **Status**: Infrastructure ready, pending real-task test
- **delegate.sh**: Auto-injects lessons + skills into agent prompts before spawning
- **self-improve.sh**: 5 bash checks (patterns, health, selectors, lessons, sync) — 0 tokens
- **Cron**: 10:00 + 22:00 daily, bash-only, agent wakes only on alert
- **Lessons**: 57 cleaned (was 122), inject-lessons.sh does TF-IDF search
- **Token rule**: NO background token burn. Cron = bash. Agent only when needed.
- **Next**: Test with real task to validate full flow
- **Key scripts**: `swarm/delegate.sh`, `swarm/inject-lessons.sh`, `swarm/self-improve.sh`

## 🚨 חוק ברזל
- כל משימה → דרך מערכת הסוכנים (koder/shomer/tzayar/bodek)
- אסור לי לכתוב קוד בעצמי
- sandbox בלבד, פרודקשן רק באישור יוסי
- עקיפה: רק אם יוסי אומר "תעשה אתה"

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

## Claude Code CLI (מ-20/02/2026)
- **מותקן:** v2.1.44, עובד עם `-p` mode
- **Flow:** אור → Claude Code CLI → כותב קוד → אור בודק → production
- **בעיית SIGKILL נפתרה (20/02):**
  - סיבה 1: הרשאות חסרות ב-`~/.claude/settings.local.json` — הוספנו `Bash(*) Read(*) Write(*) Edit(*)`
  - סיבה 2: `claude -p` בפורמט text לא מוציא output בזמן עבודה → OpenClaw `noOutputTimeout` הורג אותו
  - **פתרון:** תמיד להריץ עם `--verbose --output-format stream-json`
  - דוגמה: `claude -p --verbose --output-format stream-json "task"`
- **Skill file:** `/usr/lib/node_modules/openclaw/skills/coding-agent/SKILL.md`

## לקחים חשובים

### DB Cleanup Disaster (05/03/2026)
- שלחתי קודר ל"clean E2E junk" — הוא מחק הכל כולל demo data
- **חוק ברזל חדש:** כל cleanup/delete task חייב לכלול:
  1. רשימה מפורשת של מה למחוק (regex patterns)
  2. רשימה מפורשת של מה **לא** לגעת (demo agents, real skills)
  3. `countDocuments()` לפני ואחרי — אם count יורד ביותר מ-50% → עצור ושאל
- **חוק ברזל חדש:** אחרי כל סוכן שמשנה DB, לבדוק counts: agents, skills, posts — לא רק "tests pass"
- **חוק ברזל חדש:** ליצור seed-all.js שאפשר תמיד לשחזר ממנו

### 20/02/2026
- **לעולם לא לכתוב קוד בעצמי** — תמיד דרך Claude Code CLI או סוכנים
- **לעולם לא לעבוד על production** — sandbox בלבד
- **לא להוסיף משימות** שיוסי לא ביקש
- **לבדוק בעצמי בדפדפן** לפני שאומר "הכל עובד"
- **לענות מיד** כשיוסי שולח הודעה — לא להיתקע ב-tool calls ארוכים
