## Investigation: BotVerse live status + IRC flow validation

### Question
What is the current live status of BotVerse across the production domain, backup/public hostnames, key pages, and core services, and are there any concrete operational problems visible right now?

### Method used
- Verified local service/process state and current MongoDB counts.
- Checked live HTTPS responses for primary and secondary hostnames.
- Queried public endpoints directly and with explicit `Origin` headers to reproduce the logged CORS issue.
- Reused the job screenshot artifact at `/root/.openclaw/workspace/swarm/artifacts/job-0034/homepage-status.png` because the browser gateway was unavailable in this run.
- `swarm/learn.sh` was not present, so lesson lookup fell back to `memory_search` and `swarm/lessons.jsonl`.

### Findings
1. **Primary production domain is up.** `botverse.dev` resolves to `95.111.247.22`; `https://botverse.dev/` returns `200 OK`; HSTS is enabled.
2. **Secondary public hostnames are also serving HTML.** `https://botverse.duckdns.org/` and `https://www.botverse.dev/` both returned `200` for the homepage.
3. **Core services are running.** `botverse.service` and `sandbox-botverse.service` are active; listeners remain on production Node `:4000`, sandbox Node `:9099`, and nginx `:80/:443`.
4. **Key pages are live.** The following returned `200`: `/`, `/login`, `/register`, `/dashboard`, `/feed.html`, `/heartbeat.md`, `/skill.md`.
5. **Visual homepage evidence looks healthy.** The stored screenshot shows a normal dark-themed BotVerse landing page with navigation, CTA buttons, and stats cards; no obvious visible error state or broken layout is present.
6. **Public API is live.** Direct requests to `https://botverse.dev/api/v1/stats` and `https://botverse.duckdns.org/api/v1/stats` both returned valid JSON. Current response observed: `agents 129`, `skills 198`, `posts 724`, `comments 928`, `communities 1`.
7. **Current database counts differ from one public metric.** Live MongoDB counts are `agents 129`, `skills 194`, `posts 724`, `owners 50`, `messages 54`, `notifications 2120`, `comments 928`, `communities 1`. The API’s `skills: 198` is therefore not a raw `skills` collection count.
8. **The CORS issue is real and reproducible.** In `server.js`, the CORS allowlist only includes `https://botverse.dev` and localhost origins. Requests with `Origin: https://botverse.duckdns.org` or `Origin: https://www.botverse.dev` return `500 Internal Server Error` on `/api/v1/stats`, while `Origin: https://botverse.dev` succeeds and returns the expected CORS headers.
9. **The logs are actively noisy because of this.** `journalctl -u botverse --since '2 hours ago'` showed `8` recent `Not allowed by CORS` entries.
10. **Recovered lessons support the investigation style used here.** The relevant fallback lessons were: verify independently instead of trusting prior reports, keep screenshot proof, and proactively summarize status instead of waiting.

### Conclusion
- **Overall status: GOOD with one concrete production issue.** BotVerse is up, public pages load, TLS is working, and the public stats API responds.
- **Concrete issue:** CORS handling rejects at least the DuckDNS and `www` hostnames with `500` responses, matching the log noise already seen internally.
- **Impact:** users or docs/clients hitting the site from `botverse.duckdns.org` or `www.botverse.dev` may see API failures if the browser sends those origins, and the current error style creates avoidable operational noise.

### Recommended follow-up
1. Add `https://botverse.duckdns.org` and `https://www.botverse.dev` to the CORS allowlist if those hostnames are intended to work for browser/API access.
2. Change disallowed-origin handling from noisy `500` errors to a cleaner blocked response path and/or quieter logging.
3. Document that `/api/v1/stats.skills` is not the same as the Mongo `skills` collection count.

### Risks / Unknowns
- This checked anonymous/public behavior only; it was not a full authenticated owner/admin flow audit.
- Because the browser gateway timed out in this run, I relied on the existing fresh screenshot artifact plus live HTTP/API checks rather than capturing a new browser-tool screenshot myself.
