# ISRAWAR Full Audit Report
**Date:** 2026-03-16 02:35 CET  
**URL:** http://localhost:3200 (dev server on port 3200, NOT 3000)  
**Project:** /root/pharos-ai  
**Stack:** Next.js 16.1.6 + React 19.2.3 + TypeScript + Tailwind + Prisma 7 + PostgreSQL 16

---

## Executive Summary

The site is functional but **has no automated data ingestion pipeline**. All data was either seeded or manually ingested via one-off API calls. The core application works — APIs return data, RSS feeds fetch live, the dashboard renders — but content goes stale because nothing triggers the ingest endpoint on a schedule.

---

## Issues Found

### 🔴 CRITICAL

#### 1. No Cron/Scheduler for Data Ingestion
- **What:** The `/api/v1/rss/ingest` endpoint exists and works (it fetches RSS feeds, extracts events via Gemini AI, and saves to DB). But **nothing calls it automatically**.
- **Evidence:** No crontab entry for pharos. No Vercel cron config. No background worker. No setInterval-based scheduler in code.
- **Impact:** Events only appear when someone manually POSTs to `/api/v1/rss/ingest`. Last ingest was ~01:38 UTC today (88 events created). Before that, only 139 seed events from Mar 13.
- **Fix:** Add a cron job: `*/30 * * * * curl -s -X POST http://localhost:3200/api/v1/rss/ingest > /dev/null 2>&1` or add Vercel cron config, or build an internal scheduler.

#### 2. GEMINI_API_KEY Not Set in .env.local
- **What:** The ingest pipeline requires `GEMINI_API_KEY` to extract events from RSS via Gemini AI. This key is not in `.env.local`.
- **Evidence:** `grep "GEMINI" .env.local` returns nothing. The ingest endpoint times out/fails without it.
- **Impact:** Even if a cron existed, ingest would fail without this key.
- **Fix:** Add `GEMINI_API_KEY=<key>` to `.env.local`.

#### 3. Day Snapshots Stop at March 3rd (Only 4 Days)
- **What:** `ConflictDaySnapshot` table only has 4 entries (Feb 28 – Mar 3), all from initial seed data. No new snapshots have been created since.
- **Evidence:** `SELECT day FROM ConflictDaySnapshot ORDER BY day DESC` → 2026-03-03, 03-02, 03-01, 02-28
- **Impact:** The dashboard's day-by-day view, brief widgets, casualties widget, key facts widget — all rely on day snapshots. They show stale data from Day 4 of the conflict (now Day 16+).
- **Fix:** Need a mechanism to create daily snapshots. Either:
  - An admin API endpoint to generate snapshots from events
  - An automated agent/cron that summarizes each day's events into a snapshot
  - The "agent layer" mentioned in README (not yet open-sourced)

### 🟡 HIGH

#### 4. Dev Server Running on Port 3200, Not 3000
- **What:** The Next.js dev server runs on port 3200 (`next dev -p 3200`), but `.env.local` has `NEXT_PUBLIC_APP_URL=http://localhost:3000`.
- **Evidence:** `curl localhost:3000` returns 302 (something else), `curl localhost:3200` returns 307 (Next.js redirect to /dashboard).
- **Impact:** OG image URLs, sitemap, canonical URLs all reference port 3000 incorrectly.
- **Fix:** Either run on port 3000 or update `NEXT_PUBLIC_APP_URL`.

#### 5. Root URL Returns 404 for API Routes Like `/api/v1/conflicts/iran-2026/map`
- **What:** `/api/v1/conflicts/iran-2026/map` returns a 404 (HTML not-found page). The actual endpoints are `/map/data` and `/map/stories`.
- **Evidence:** `curl localhost:3200/api/v1/conflicts/iran-2026/map` returns HTML 404
- **Impact:** Minor — sub-routes work fine. But could confuse API consumers.

#### 6. Supabase Credentials Are Placeholder
- **What:** `.env.local` has `NEXT_PUBLIC_SUPABASE_URL="https://your-project-ref.supabase.co"` and dummy keys.
- **Evidence:** Direct from .env.local contents
- **Impact:** Any Supabase-dependent features (auth, storage, realtime) won't work. Currently using local PostgreSQL which works fine for data.
- **Fix:** Configure real Supabase credentials or ensure local-only mode is fully supported.

#### 7. XAI_API_KEY Is Placeholder
- **What:** `XAI_API_KEY="xai-xxx"` — placeholder value.
- **Evidence:** Direct from .env.local
- **Impact:** Tweet verification and X post discovery features won't work.

### 🟠 MEDIUM

#### 8. RSS Feed Errors (2 of 30)
- **What:** 2 RSS feeds fail:
  - `timesofisrael`: HTTP 403 (blocked)
  - `presstv`: Parse error (`content.match is not a function`)
- **Evidence:** POST `/api/v1/rss/fetch` response
- **Impact:** 2 of 30 feeds don't provide data. 28 work fine.
- **Fix:** Times of Israel may need different User-Agent or direct URL. PressTV parser needs error handling fix.

#### 9. No Conflict Summary/Escalation Updates
- **What:** The main conflict record (`Conflict` table) has static data from seed. Escalation stuck at 94, summary describes Day 4 events only.
- **Evidence:** API returns `escalation: 94`, summary references "Day 4" events, but it's now Day 16+.
- **Impact:** Dashboard summary bar shows outdated conflict status.
- **Fix:** Need automated or manual updates to the conflict record.

#### 10. NEXT_PUBLIC_API_URL Points to Port 8100 (Unused)
- **What:** `.env.local` has `NEXT_PUBLIC_API_URL=http://localhost:8100/api/news` — but the app uses relative `/api/v1` paths.
- **Evidence:** `src/shared/lib/query/client.ts` uses `const BASE = '/api/v1'`
- **Impact:** None currently (the variable is unused by the client). But confusing.
- **Fix:** Remove or update the unused env var.

### 🟢 LOW

#### 11. No TODO/FIXME/HACK Comments in Code
- **What:** grep found zero TODO/FIXME/HACK markers in src/.
- **Impact:** Good — code is clean.

#### 12. Auto-refresh Exists but Only for Client-Side
- **What:** `useBrowseAutoRefresh` hook calls `router.refresh()` every 4 minutes, which re-fetches server component data.
- **Impact:** This works for refreshing already-fetched data from DB, but doesn't help if no new data is being ingested.

---

## What Works

| Feature | Status | Notes |
|---------|--------|-------|
| PostgreSQL | ✅ Working | Docker container, port 5434 |
| RSS Feed Fetching | ✅ Working | 28/30 feeds return live data |
| Events API | ✅ Working | 227 events, latest from today |
| Actors API | ✅ Working | 10 actors with data |
| X Posts API | ✅ Working | 55 posts (seed data) |
| Map Data API | ✅ Working | Strikes, missiles, targets, assets, threat zones |
| Map Stories API | ✅ Exists | Not verified content |
| Daily Briefs RSS | ✅ Working | Returns RSS XML with 4 day briefs |
| Day Snapshots API | ⚠️ Stale | Only 4 days (seed data) |
| Ingest Pipeline | ⚠️ Manual | Works but not automated |
| Client Auto-refresh | ✅ Working | 4-min interval |

---

## Recommended Priority Actions

1. **Add GEMINI_API_KEY** to `.env.local` → enables the ingest pipeline
2. **Add cron job** to call `/api/v1/rss/ingest` every 30 minutes
3. **Build day snapshot generator** — either API endpoint or automated job that creates daily snapshots from events
4. **Update conflict record** — escalation, summary, key facts need to reflect current state (Day 16+)
5. **Fix port mismatch** — run on 3000 or update env vars
6. **Fix broken RSS feeds** — Times of Israel (403) and PressTV (parser error)

---

## Architecture Notes

The README mentions an "internal agent layer that ingests and prepares data" which is "not yet included" in the open source release. This is the missing piece — the application layer is complete and functional, but the data pipeline (agent layer) that should:
- Periodically fetch RSS feeds
- Extract events via AI
- Generate day snapshots
- Update conflict status
- Verify X/Twitter posts

...does not exist in this codebase. The `/api/v1/rss/ingest` endpoint is a partial solution but needs to be called externally and lacks day snapshot generation.
