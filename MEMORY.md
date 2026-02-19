# MEMORY.md - Long-Term Memory

## About Yossi (יוסי)
- Hebrew speaker, prefers Hebrew
- Telegram ID: 8487535487
- Timezone: Europe/Berlin (GMT+1)
- Named me אור (Or) on 2026-02-02

## Projects
| Project | Folder | URL | Services |
|---------|--------|-----|----------|
| פוקר | `/root/TexasPokerGame` | `zozopoker.duckdns.org` | texas-poker, poker-client, poker-admin |
| בלאקג'ק | `/root/Blackjack-Game-Multiplayer` | `95.111.247.22:3000` | blackjack |
| הימורים | `/root/BettingPlatform` | `95.111.247.22:8089` | betting-backend, betting-aggregator |

## VPS: 95.111.247.22
- VNC :5901 (password: desktop1)
- Sandbox: `/root/sandbox/<project>`

## Key Lessons
- ALWAYS sandbox + screenshots + approval before production
- NEVER code directly as orchestrator — delegate to koder
- BetsAPI inplay returns ALL sports (sport_id param ignored)
- Events filter 12h+ not 3h
- Don't burn tokens — bash for monitoring, AI only when needed
