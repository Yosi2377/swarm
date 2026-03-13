# Swarm Engine v3 — Production Orchestration System

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  CALLER (orchestrator)           │
│  1. run.sh "task" → JSON                        │
│  2. sessions_spawn with prompt from JSON         │
│  3. Wait for done_marker                         │
│  4. verify.sh checks_file → PASS/FAIL           │
│  5. If FAIL: retry-prompt.sh → re-spawn          │
│  6. report.sh → Telegram + lessons               │
└──────┬──────────┬───────────┬───────────────────┘
       │          │           │
  ┌────▼───┐ ┌───▼────┐ ┌───▼─────┐
  │ run.sh │ │verify  │ │report   │
  │        │ │.sh     │ │.sh      │
  └───┬────┘ └───┬────┘ └───┬─────┘
      │          │           │
  ┌───▼──────────▼───────────▼──────┐
  │  check.sh  smart-check.sh       │
  │  learn.sh  retry-prompt.sh      │
  │  create-topic.sh  send.sh       │
  └─────────────────────────────────┘
```

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `run.sh` | Main pipeline — outputs JSON for caller | `run.sh "task" [project] [url]` |
| `smart-check.sh` | Generate checks from task description | `smart-check.sh "task" [project] [url]` |
| `verify.sh` | Run checks file, return PASS/FAIL | `verify.sh <checks_file>` |
| `retry-prompt.sh` | Enrich prompt with failure details | `retry-prompt.sh <prompt> <errors> <N>` |
| `report.sh` | Report to Telegram + save lesson | `report.sh <agent> <thread> <status> <summary>` |
| `check.sh` | Individual check commands | `check.sh <type> <args...>` |
| `learn.sh` | Save/query/inject lessons | `learn.sh save\|query\|inject ...` |
| `status.sh` | Show engine status | `status.sh` |

## Example Full Flow

```bash
# 1. Prepare task
JSON=$(bash engine/run.sh "שנה שם מ-ABC ל-XYZ" /root/pharos-ai http://localhost:3200)
AGENT=$(echo "$JSON" | jq -r .agent)
THREAD=$(echo "$JSON" | jq -r .thread)
PROMPT=$(echo "$JSON" | jq -r .prompt)

# 2. Spawn agent (caller does this via sessions_spawn)
# ... agent works ...

# 3. Verify
echo "$JSON" | jq -r '.checks[]' > /tmp/checks.txt
bash engine/verify.sh /tmp/checks.txt
# Exit 0 = PASS, 1 = FAIL

# 4. On failure — retry
RETRY=$(bash engine/retry-prompt.sh "$PROMPT_FILE" "❌ ABC still found" 2)
# Re-spawn with $RETRY as prompt file

# 5. Report
bash engine/report.sh "$AGENT" "$THREAD" pass "Renamed ABC→XYZ"
```

## Retry Logic

1. `run.sh` sets `max_retries: 3` and `timeout_seconds: 300`
2. Caller spawns agent, waits for `done_marker` or timeout
3. On completion: `verify.sh` runs all checks
4. On FAIL: `retry-prompt.sh` creates enriched prompt with:
   - Original task
   - Exact failure details
   - Timeout-specific guidance if applicable
5. Caller re-spawns with new prompt
6. After max retries: `report.sh` with fail status

## Lessons System

- `learn.sh save <agent> <task> <pass|fail> <lesson>` — stores in `lessons.json`
- `learn.sh inject <agent> <task>` — returns relevant past lessons for prompt enrichment
- `run.sh` auto-injects lessons into prompts
- `report.sh` auto-saves lessons after each task

## Check Types

| Check | Args | What it does |
|-------|------|-------------|
| `http_status` | `<url> [code]` | HTTP response code |
| `git_changed` | `<repo> [min]` | Minimum git changes |
| `grep_content` | `<url> <text>` | Text present in page |
| `grep_content_absent` | `<url> <text>` | Text NOT in page |
| `no_console_errors` | `<url>` | Zero JS console errors |
| `file_exists` | `<path>` | File exists with size > 0 |
| `screenshot` | `<url> <path>` | Take screenshot |
| `process_running` | `<pattern>` | Process alive |
