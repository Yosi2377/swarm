#!/bin/bash
# learn.sh v2 — Agent Learning System
# Full CLI with subcommands for tracking, analysis, and feedback
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEARN_DIR="$(cd "$SCRIPT_DIR/../learning" && pwd)"
LESSONS_FILE="$LEARN_DIR/lessons.json"
METRICS_FILE="$LEARN_DIR/metrics.json"
SCORES_FILE="$LEARN_DIR/scores.json"
QUALITY_FILE="$LEARN_DIR/quality.json"
PATTERNS_FILE="$LEARN_DIR/patterns.json"
TASK_LOG="$LEARN_DIR/task_log.json"
ALERTS_FILE="$LEARN_DIR/alerts.json"

# Ensure files exist
for f in "$LESSONS_FILE" "$SCORES_FILE" "$QUALITY_FILE" "$PATTERNS_FILE" "$ALERTS_FILE"; do
  [[ -f "$f" ]] || echo '{}' > "$f"
done
[[ -f "$METRICS_FILE" ]] || echo '{"tasks":[],"agent_stats":{}}' > "$METRICS_FILE"
[[ -f "$TASK_LOG" ]] || echo '[]' > "$TASK_LOG"

usage() {
  cat <<'EOF'
learn.sh v2 — Agent Learning System

USAGE:
  learn.sh <command> [args...]

RECORDING:
  save <agent> <task> <pass|fail> <lesson>     Save a lesson (backward compat)
  record <agent> <task_id> <status> [options]  Record task with full metrics
    --category <cat>          Failure category (code_error|timeout|wrong_approach|missing_dependency|environment|unclear_task)
    --reason <text>           Why it failed/succeeded
    --duration <seconds>      Task duration
    --retry <count>           Retry count
    --quality <1-10>          Code quality score
    --manual                  Mark as manual intervention
    --lint-errors <count>     Lint error count
    --task-type <type>        Task type for grouping
  start <agent> <task_id>                      Mark task start time
  end <agent> <task_id> <pass|fail> [reason]   Mark task end + auto-duration

QUERYING:
  query <keywords> [max]       Search lessons by keywords
  inject <agent> <task_desc>   Get TOP 5 relevant lessons for a task
  why-fail <task_id>           Show failure details for a task
  agent <name>                 Detailed agent report
  dashboard                   Overview dashboard
  trends [agent]               ASCII trend chart
  stats                       Quick stats summary

MANAGEMENT:
  check-drift                 Check for agent performance drift
  effectiveness               Show lesson effectiveness stats
  export [agent]              Export data as JSON
  test                        Run self-tests

EOF
}

# ── Helpers ──────────────────────────────────────────────
_jq_safe() {
  local file="$1"; shift
  local tmp="${file}.tmp.$$"
  if jq "$@" "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}

_gen_id() {
  printf '%08x' $((RANDOM * RANDOM))
}

_now() {
  date -Iseconds
}

_ensure_lessons_array() {
  # Handle both formats: {version:1,lessons:[...]} and [...]
  local fmt
  fmt=$(jq -r 'type' "$LESSONS_FILE" 2>/dev/null)
  if [[ "$fmt" == "object" ]]; then
    # Already object format, fine
    :
  elif [[ "$fmt" == "array" ]]; then
    # Convert array to object
    _jq_safe "$LESSONS_FILE" '{version:2, lessons:.}'
  else
    echo '{"version":2,"lessons":[]}' > "$LESSONS_FILE"
  fi
}

_get_lessons() {
  _ensure_lessons_array
  jq -c '.lessons // []' "$LESSONS_FILE"
}

_add_lesson() {
  local entry="$1"
  _ensure_lessons_array
  _jq_safe "$LESSONS_FILE" --argjson e "$entry" '.lessons += [$e] | .version = 2'
}

# ── Commands ─────────────────────────────────────────────

cmd_save() {
  # Backward compatible: save <agent> <task> <pass|fail> <lesson>
  [[ $# -lt 4 ]] && { echo "Usage: learn.sh save <agent> <task> <pass|fail> <lesson>"; exit 1; }
  local agent="$1" task="$2" result="$3" lesson="$4"
  local id=$(_gen_id)
  local severity="low"
  [[ "$result" == "fail" ]] && severity="medium"
  
  local entry
  entry=$(jq -n --arg id "$id" --arg a "$agent" --arg t "$task" --arg r "$result" \
    --arg l "$lesson" --arg s "$severity" --arg ts "$(_now)" \
    '{id:$id, agent:$a, task:$t, result:$r, lesson:$l, severity:$s, impact:0.5, timestamp:$ts, applied:0}')
  
  _add_lesson "$entry"
  
  # Also record in metrics and scores
  local mapped_status="$result"
  [[ "$result" == "pass" ]] || mapped_status="fail"
  _record_metric "$agent" "$task" "$mapped_status" "" "" "" "" "" "" ""
  _update_scores "$agent" "$mapped_status"
  
  echo "✅ Saved lesson for $agent: $lesson"
}

cmd_record() {
  # Full recording: record <agent> <task_id> <status> [options]
  [[ $# -lt 3 ]] && { echo "Usage: learn.sh record <agent> <task_id> <pass|fail> [--category ...] [--reason ...]"; exit 1; }
  local agent="$1" task_id="$2" status="$3"
  shift 3
  
  local category="" reason="" duration="" retry="" quality="" manual="false" lint_errors="" task_type=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category) category="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --duration) duration="$2"; shift 2 ;;
      --retry) retry="$2"; shift 2 ;;
      --quality) quality="$2"; shift 2 ;;
      --manual) manual="true"; shift ;;
      --lint-errors) lint_errors="$2"; shift 2 ;;
      --task-type) task_type="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  
  # Auto-categorize if fail and no category given
  if [[ "$status" == "fail" && -z "$category" ]]; then
    category="unknown"
    # Try to guess from reason
    if [[ -n "$reason" ]]; then
      case "$reason" in
        *timeout*|*timed*out*) category="timeout" ;;
        *lint*|*syntax*|*error*|*bug*|*undefined*) category="code_error" ;;
        *missing*|*not*found*|*install*) category="missing_dependency" ;;
        *approach*|*wrong*|*redesign*) category="wrong_approach" ;;
        *env*|*permission*|*docker*) category="environment" ;;
        *unclear*|*ambiguous*|*spec*) category="unclear_task" ;;
      esac
    fi
  fi
  
  _record_metric "$agent" "$task_id" "$status" "$category" "$reason" "$duration" "$retry" "$quality" "$lint_errors" "$task_type"
  
  # Auto-generate lesson from failure
  if [[ "$status" == "fail" && -n "$reason" ]]; then
    local severity="medium"
    [[ -n "$retry" && "$retry" -ge 3 ]] && severity="high"
    local id=$(_gen_id)
    local entry
    entry=$(jq -n --arg id "$id" --arg a "$agent" --arg t "$task_id" --arg r "fail" \
      --arg l "$reason" --arg s "$severity" --arg c "$category" --arg ts "$(_now)" \
      '{id:$id, agent:$a, task:$t, result:$r, lesson:$l, severity:$s, category:$c, impact:0.7, timestamp:$ts, applied:0}')
    _add_lesson "$entry"
  fi
  
  # Update scores
  _update_scores "$agent" "$status"
  
  # Update quality if provided
  if [[ -n "$quality" ]]; then
    _record_quality "$agent" "$task_id" "$quality" "$lint_errors"
  fi
  
  # Check drift
  _check_drift_silent "$agent"
  
  echo "✅ Recorded: $agent/$task_id → $status${category:+ [$category]}${reason:+ ($reason)}"
}

_record_metric() {
  local agent="$1" task_id="$2" status="$3" category="$4" reason="$5"
  local duration="$6" retry="$7" quality="$8" lint_errors="$9" task_type="${10}"
  
  local entry
  entry=$(jq -n \
    --arg a "$agent" --arg t "$task_id" --arg s "$status" \
    --arg c "${category:-}" --arg r "${reason:-}" \
    --arg d "${duration:-0}" --arg rt "${retry:-0}" \
    --arg q "${quality:-0}" --arg le "${lint_errors:-0}" \
    --arg tt "${task_type:-general}" --arg ts "$(_now)" \
    --arg manual "${manual:-false}" \
    '{
      agent: $a, task_id: $t, status: $s, category: $c, reason: $r,
      duration_seconds: ($d|tonumber), retry_count: ($rt|tonumber),
      quality_score: ($q|tonumber), lint_errors: ($le|tonumber),
      task_type: $tt, manual_intervention: ($manual == "true"),
      timestamp: $ts
    }')
  
  _jq_safe "$METRICS_FILE" --argjson e "$entry" '.tasks += [$e]'
  
  # Update agent stats
  _jq_safe "$METRICS_FILE" --arg a "$agent" --arg s "$status" --arg d "${duration:-0}" --arg q "${quality:-0}" \
    '.agent_stats[$a] = (
      (.agent_stats[$a] // {total:0, success:0, fail:0, total_duration:0, total_quality:0, quality_count:0, manual_count:0, total_retries:0}) |
      .total += 1 |
      (if $s == "pass" then .success += 1 else .fail += 1 end) |
      .total_duration += ($d|tonumber) |
      (if ($q|tonumber) > 0 then .total_quality += ($q|tonumber) | .quality_count += 1 else . end)
    )'
}

_update_scores() {
  local agent="$1" status="$2"
  local inc_s=0 inc_f=0
  [[ "$status" == "pass" ]] && inc_s=1 || inc_f=1
  
  _jq_safe "$SCORES_FILE" --arg a "$agent" --argjson s "$inc_s" --argjson f "$inc_f" \
    '.agents[$a] = (
      (.agents[$a] // {tasks:0, success:0, fail:0, score:50, streak:0}) |
      .tasks += 1 | .success += $s | .fail += $f |
      .score = (if .tasks > 0 then ((.success * 100) / .tasks | round) else 50 end) |
      .streak = (if $s == 1 then (if .streak >= 0 then .streak + 1 else 1 end) else (if .streak <= 0 then .streak - 1 else -1 end) end)
    )'
}

_record_quality() {
  local agent="$1" task_id="$2" quality="$3" lint_errors="${4:-0}"
  _jq_safe "$QUALITY_FILE" --arg a "$agent" --arg t "$task_id" --arg q "$quality" --arg le "$lint_errors" --arg ts "$(_now)" \
    '.reviews += [{agent:$a, taskId:$t, score:($q|tonumber), lint_errors:($le|tonumber), timestamp:$ts}] |
     .agentAverages[$a] = ([.reviews[] | select(.agent==$a) | .score] | add / length | . * 10 | round / 10)'
}

cmd_start() {
  [[ $# -lt 2 ]] && { echo "Usage: learn.sh start <agent> <task_id>"; exit 1; }
  local agent="$1" task_id="$2"
  local start_file="$LEARN_DIR/.start_${agent}_${task_id}"
  date +%s > "$start_file"
  echo "⏱️ Timer started for $agent/$task_id"
}

cmd_end() {
  [[ $# -lt 3 ]] && { echo "Usage: learn.sh end <agent> <task_id> <pass|fail> [reason]"; exit 1; }
  local agent="$1" task_id="$2" status="$3" reason="${4:-}"
  local start_file="$LEARN_DIR/.start_${agent}_${task_id}"
  local duration=0
  
  if [[ -f "$start_file" ]]; then
    local start_ts
    start_ts=$(cat "$start_file")
    duration=$(( $(date +%s) - start_ts ))
    rm -f "$start_file"
  fi
  
  cmd_record "$agent" "$task_id" "$status" --duration "$duration" ${reason:+--reason "$reason"}
  echo "⏱️ Duration: ${duration}s"
}

cmd_query() {
  [[ $# -lt 1 ]] && { echo "Usage: learn.sh query <keywords> [max_results]"; exit 1; }
  local keywords="$1" max="${2:-5}"
  local pattern
  pattern=$(echo "$keywords" | tr ' ' '|')
  _get_lessons | jq -c '.[]' | grep -iE "$pattern" | head -n "$max"
}

cmd_inject() {
  [[ $# -lt 2 ]] && { echo "Usage: learn.sh inject <agent_id> <task_description>"; exit 1; }
  local agent="$1" task_desc="$2"
  
  # Get relevant lessons: same agent + keyword match + high impact first
  local keywords
  keywords=$(echo "$task_desc" | tr -cs 'a-zA-Z0-9' '\n' | sort -u | head -20 | tr '\n' '|' | sed 's/|$//')
  
  local results
  results=$(_get_lessons | jq -c "[.[] | select(
    .agent == \"$agent\" or 
    (.lesson // \"\" | test(\"${keywords:0:100}\"; \"i\") // false) or
    (.task // \"\" | test(\"${keywords:0:100}\"; \"i\") // false)
  )] | sort_by(-.impact, -.applied) | .[0:5]" 2>/dev/null)
  
  [[ -z "$results" || "$results" == "[]" ]] && exit 0
  
  echo "## 📚 Lessons from past tasks:"
  echo "$results" | jq -r '.[] | "- [\(.severity // "low")] \(.lesson // .what)"'
  
  # Track that these lessons were applied
  local ids
  ids=$(echo "$results" | jq -r '.[].id // empty')
  for id in $ids; do
    _jq_safe "$LESSONS_FILE" --arg id "$id" \
      '.lessons = [.lessons[] | if .id == $id then .applied += 1 else . end]' 2>/dev/null || true
  done
}

cmd_why_fail() {
  [[ $# -lt 1 ]] && { echo "Usage: learn.sh why-fail <task_id>"; exit 1; }
  local task_id="$1"
  
  echo "═══════════════════════════════════════"
  echo "  🔍 Failure Analysis: Task $task_id"
  echo "═══════════════════════════════════════"
  
  # From metrics
  local task_data
  task_data=$(jq -c "[.tasks[] | select(.task_id == \"$task_id\")]" "$METRICS_FILE" 2>/dev/null)
  
  if [[ -n "$task_data" && "$task_data" != "[]" ]]; then
    echo ""
    echo "📊 Task Records:"
    echo "$task_data" | jq -r '.[] | "  Status: \(.status) | Category: \(.category // "n/a") | Duration: \(.duration_seconds)s | Retries: \(.retry_count) | Quality: \(.quality_score)"'
    echo ""
    echo "📝 Reasons:"
    echo "$task_data" | jq -r '.[] | select(.reason != "" and .reason != null) | "  → \(.reason)"'
  fi
  
  # From lessons
  local lessons
  lessons=$(_get_lessons | jq -c "[.[] | select(.task // \"\" | contains(\"$task_id\"))]")
  
  if [[ -n "$lessons" && "$lessons" != "[]" ]]; then
    echo ""
    echo "📚 Related Lessons:"
    echo "$lessons" | jq -r '.[] | "  [\(.severity)] \(.what // ""): \(.lesson // "")"'
  fi
  
  [[ "$task_data" == "[]" && "$lessons" == "[]" ]] && echo "  No data found for task $task_id"
}

cmd_agent() {
  [[ $# -lt 1 ]] && { echo "Usage: learn.sh agent <name>"; exit 1; }
  local agent="$1"
  
  echo "═══════════════════════════════════════"
  echo "  📋 Agent Report: $agent"
  echo "═══════════════════════════════════════"
  
  # From scores
  local score_data
  score_data=$(jq -c ".agents.\"$agent\" // {}" "$SCORES_FILE" 2>/dev/null)
  
  echo ""
  echo "📊 Overall:"
  echo "$score_data" | jq -r '"  Tasks: \(.tasks // 0) | Success: \(.success // 0) | Fail: \(.fail // 0) | Score: \(.score // 0)% | Streak: \(.streak // 0)"'
  
  # From metrics
  local stats
  stats=$(jq -c ".agent_stats.\"$agent\" // {}" "$METRICS_FILE" 2>/dev/null)
  
  if [[ -n "$stats" && "$stats" != "{}" ]]; then
    echo ""
    echo "⏱️ Performance:"
    echo "$stats" | jq -r '"  Avg Duration: \(if .total > 0 then (.total_duration / .total | round) else 0 end)s | Avg Quality: \(if .quality_count > 0 then (.total_quality / .quality_count * 10 | round / 10) else "n/a" end)"'
  fi
  
  # First attempt success rate
  local first_success_rate
  first_success_rate=$(jq -r "[.tasks[] | select(.agent == \"$agent\" and .retry_count == 0 and .status == \"pass\")] | length" "$METRICS_FILE" 2>/dev/null)
  local total_first
  total_first=$(jq -r "[.tasks[] | select(.agent == \"$agent\" and .retry_count == 0)] | length" "$METRICS_FILE" 2>/dev/null)
  
  if [[ "$total_first" -gt 0 ]] 2>/dev/null; then
    echo "  First Attempt Success: $first_success_rate/$total_first ($(( first_success_rate * 100 / total_first ))%)"
  fi
  
  # Manual intervention rate
  local manual_count
  manual_count=$(jq -r "[.tasks[] | select(.agent == \"$agent\" and .manual_intervention == true)] | length" "$METRICS_FILE" 2>/dev/null)
  local agent_total
  agent_total=$(jq -r "[.tasks[] | select(.agent == \"$agent\")] | length" "$METRICS_FILE" 2>/dev/null)
  
  if [[ "$agent_total" -gt 0 ]] 2>/dev/null; then
    echo "  Manual Interventions: $manual_count/$agent_total ($(( manual_count * 100 / agent_total ))%)"
  fi
  
  # Failure categories
  echo ""
  echo "❌ Failure Categories:"
  jq -r "[.tasks[] | select(.agent == \"$agent\" and .status == \"fail\" and .category != \"\")] | group_by(.category) | .[] | \"  \(.[0].category): \(length)\"" "$METRICS_FILE" 2>/dev/null || echo "  No categorized failures"
  
  # Quality history
  echo ""
  echo "📈 Quality:"
  local avg_quality
  avg_quality=$(jq -r ".agentAverages.\"$agent\" // \"n/a\"" "$QUALITY_FILE" 2>/dev/null)
  echo "  Average Quality Score: $avg_quality"
  
  # Recent lessons
  echo ""
  echo "📚 Recent Lessons (last 5):"
  _get_lessons | jq -r "[.[] | select(.agent == \"$agent\")] | sort_by(.timestamp) | reverse | .[0:5][] | \"  [\(.severity // \"low\")] \(.lesson // .what // \"\")\""
}

cmd_dashboard() {
  echo "╔═══════════════════════════════════════════════════╗"
  echo "║          🧠 Learning System v2 Dashboard         ║"
  echo "╚═══════════════════════════════════════════════════╝"
  echo ""
  
  # Total stats
  local total_tasks total_success total_fail total_lessons
  total_tasks=$(jq '[.agents[].tasks] | add // 0' "$SCORES_FILE" 2>/dev/null)
  total_success=$(jq '[.agents[].success] | add // 0' "$SCORES_FILE" 2>/dev/null)
  total_fail=$(jq '[.agents[].fail] | add // 0' "$SCORES_FILE" 2>/dev/null)
  total_lessons=$(_get_lessons | jq 'length')
  
  echo "📊 Overview:"
  echo "  Total Tasks: $total_tasks | ✅ $total_success | ❌ $total_fail | 📚 Lessons: $total_lessons"
  if [[ "$total_tasks" -gt 0 ]]; then
    echo "  Success Rate: $(( total_success * 100 / total_tasks ))%"
  fi
  echo ""
  
  # Per-agent summary
  echo "👥 Agents:"
  echo "  ┌──────────────┬───────┬─────┬──────┬───────┬────────┐"
  echo "  │ Agent        │ Tasks │ Win │ Fail │ Score │ Streak │"
  echo "  ├──────────────┼───────┼─────┼──────┼───────┼────────┤"
  jq -r '[.agents | to_entries[] | select(.value.tasks > 0)] | sort_by(-.value.tasks)[] |
    "  │ \(.key | . + "            " | .[0:12]) │ \(.value.tasks | tostring | . + "     " | .[0:5]) │ \(.value.success | tostring | . + "   " | .[0:3]) │ \(.value.fail | tostring | . + "    " | .[0:4]) │ \(.value.score | tostring | . + "%    " | .[0:5]) │ \(.value.streak | tostring | . + "      " | .[0:6]) │"' "$SCORES_FILE" 2>/dev/null
  echo "  └──────────────┴───────┴─────┴──────┴───────┴────────┘"
  
  # Failure categories
  echo ""
  echo "❌ Top Failure Categories:"
  jq -r '[.tasks[] | select(.status == "fail" and .category != "" and .category != null)] | group_by(.category) | sort_by(-length) | .[0:5][] | "  \(.[0].category): \(length) occurrences"' "$METRICS_FILE" 2>/dev/null || echo "  No categorized failures yet"
  
  # Recent activity
  echo ""
  echo "📝 Recent Activity (last 5):"
  jq -r '.tasks | sort_by(.timestamp) | reverse | .[0:5][] | "  \(.timestamp | .[0:16]) \(.agent) \(.task_id) → \(.status)\(if .category != "" and .category != null then " [\(.category)]" else "" end)"' "$METRICS_FILE" 2>/dev/null || echo "  No metrics recorded yet"
  
  # Alerts
  if [[ -f "$ALERTS_FILE" ]]; then
    local alert_count
    alert_count=$(jq '[.alerts // [] | .[] | select(.resolved != true)] | length' "$ALERTS_FILE" 2>/dev/null)
    if [[ "$alert_count" -gt 0 ]] 2>/dev/null; then
      echo ""
      echo "🚨 Active Alerts ($alert_count):"
      jq -r '[.alerts[] | select(.resolved != true)] | .[0:3][] | "  ⚠️ \(.message)"' "$ALERTS_FILE" 2>/dev/null
    fi
  fi
}

cmd_trends() {
  local agent="${1:-}"
  local filter=""
  [[ -n "$agent" ]] && filter="select(.agent == \"$agent\") |"
  
  echo "📈 Task Trends (last 30 tasks):"
  echo ""
  
  # Get last 30 tasks as pass/fail sequence
  local results
  results=$(jq -r "[.tasks[] | $filter .status] | reverse | .[0:30] | reverse | .[]" "$METRICS_FILE" 2>/dev/null)
  
  if [[ -z "$results" ]]; then
    echo "  No data yet. Record tasks with: learn.sh record <agent> <task_id> <status>"
    return
  fi
  
  # ASCII bar chart
  local line=""
  local count=0 wins=0
  while IFS= read -r s; do
    count=$((count + 1))
    if [[ "$s" == "pass" ]]; then
      line="${line}█"
      wins=$((wins + 1))
    else
      line="${line}░"
    fi
  done <<< "$results"
  
  echo "  $line"
  echo "  █=pass ░=fail | $wins/$count ($(( count > 0 ? wins * 100 / count : 0 ))%)"
  echo ""
  
  # Quality trend if available
  echo "📊 Quality Trend:"
  local qualities
  qualities=$(jq -r "[.tasks[] | $filter select(.quality_score > 0) | .quality_score] | reverse | .[0:20] | reverse | .[]" "$METRICS_FILE" 2>/dev/null)
  
  if [[ -n "$qualities" ]]; then
    local qline=""
    while IFS= read -r q; do
      local bars=$(( q ))
      local bar=""
      for ((i=0; i<bars; i++)); do bar="${bar}▓"; done
      for ((i=bars; i<10; i++)); do bar="${bar}░"; done
      qline="${qline}  ${bar} ${q}/10\n"
    done <<< "$qualities"
    echo -e "$qline"
  else
    echo "  No quality data yet"
  fi
  
  # Duration trend
  echo ""
  echo "⏱️ Duration Trend (seconds):"
  local durations
  durations=$(jq -r "[.tasks[] | $filter select(.duration_seconds > 0) | .duration_seconds] | reverse | .[0:10] | reverse | .[]" "$METRICS_FILE" 2>/dev/null)
  
  if [[ -n "$durations" ]]; then
    local max_dur=1
    while IFS= read -r d; do
      [[ "$d" -gt "$max_dur" ]] && max_dur="$d"
    done <<< "$durations"
    
    while IFS= read -r d; do
      local width=$(( d * 40 / max_dur ))
      local bar=""
      for ((i=0; i<width; i++)); do bar="${bar}▇"; done
      printf "  %-6s %s\n" "${d}s" "$bar"
    done <<< "$durations"
  else
    echo "  No duration data yet"
  fi
}

cmd_stats() {
  echo "📊 Quick Stats:"
  echo ""
  
  # Per agent one-liner
  jq -r '.agents | to_entries[] | select(.value.tasks > 0) | "\(.key): \(.value.tasks) tasks, \(.value.score)% success, streak \(.value.streak)"' "$SCORES_FILE" 2>/dev/null
  
  echo ""
  echo "Total lessons: $(_get_lessons | jq 'length')"
  echo "Total metric records: $(jq '.tasks | length' "$METRICS_FILE" 2>/dev/null)"
}

_check_drift_silent() {
  local agent="$1"
  # Check last 10 vs previous 10 tasks
  local recent_rate prev_rate
  recent_rate=$(jq -r "[.tasks[] | select(.agent == \"$agent\")] | reverse | .[0:10] | [.[] | select(.status == \"pass\")] | length" "$METRICS_FILE" 2>/dev/null)
  prev_rate=$(jq -r "[.tasks[] | select(.agent == \"$agent\")] | reverse | .[10:20] | [.[] | select(.status == \"pass\")] | length" "$METRICS_FILE" 2>/dev/null)
  
  if [[ "$prev_rate" -gt 3 && "$recent_rate" -lt $(( prev_rate * 7 / 10 )) ]] 2>/dev/null; then
    local msg="⚠️ DRIFT: $agent dropped from ${prev_rate}0% to ${recent_rate}0% success (last 10 vs prev 10)"
    echo "$msg" >&2
    _jq_safe "$ALERTS_FILE" --arg m "$msg" --arg a "$agent" --arg ts "$(_now)" \
      '.alerts = ((.alerts // []) + [{agent:$a, message:$m, timestamp:$ts, resolved:false}])'
  fi
}

cmd_check_drift() {
  echo "🔍 Checking agent drift..."
  local agents
  agents=$(jq -r '.agents | keys[]' "$SCORES_FILE" 2>/dev/null)
  local found=0
  for agent in $agents; do
    local recent prev
    recent=$(jq -r "[.tasks[] | select(.agent == \"$agent\")] | reverse | .[0:10] | [.[] | select(.status == \"pass\")] | length" "$METRICS_FILE" 2>/dev/null)
    prev=$(jq -r "[.tasks[] | select(.agent == \"$agent\")] | reverse | .[10:20] | [.[] | select(.status == \"pass\")] | length" "$METRICS_FILE" 2>/dev/null)
    
    if [[ "$prev" -gt 3 ]] 2>/dev/null; then
      local diff=$(( (prev - recent) * 100 / prev ))
      if [[ "$diff" -gt 30 ]]; then
        echo "  🚨 $agent: dropped ${diff}% (was ${prev}0%, now ${recent}0%)"
        found=1
      else
        echo "  ✅ $agent: stable (${recent}0% → prev ${prev}0%)"
      fi
    else
      echo "  ℹ️ $agent: not enough data"
    fi
  done
  [[ "$found" -eq 0 ]] && echo "  All agents stable"
}

cmd_effectiveness() {
  echo "📈 Lesson Effectiveness:"
  echo ""
  _get_lessons | jq -r 'sort_by(-.applied) | .[0:10][] | "  Applied \(.applied)x: [\(.severity // "low")] \(.lesson // .what // "" | .[0:80])"'
  
  echo ""
  echo "📊 Never-applied lessons:"
  local never
  never=$(_get_lessons | jq '[.[] | select(.applied == 0 or .applied == null)] | length')
  local total
  total=$(_get_lessons | jq 'length')
  echo "  $never/$total lessons never applied ($(( total > 0 ? never * 100 / total : 0 ))%)"
}

cmd_export() {
  local agent="${1:-}"
  if [[ -n "$agent" ]]; then
    jq -n --arg a "$agent" \
      --slurpfile s "$SCORES_FILE" \
      --slurpfile m "$METRICS_FILE" \
      --slurpfile l "$LESSONS_FILE" \
      --slurpfile q "$QUALITY_FILE" \
      '{
        agent: $a,
        scores: $s[0].agents[$a],
        metrics: [$m[0].tasks[] | select(.agent == $a)],
        lessons: [$l[0].lessons[] | select(.agent == $a)],
        quality: [$q[0].reviews[] | select(.agent == $a)]
      }'
  else
    jq -n \
      --slurpfile s "$SCORES_FILE" \
      --slurpfile m "$METRICS_FILE" \
      --slurpfile l "$LESSONS_FILE" \
      --slurpfile q "$QUALITY_FILE" \
      '{scores: $s[0], metrics: $m[0], lessons: $l[0], quality: $q[0]}'
  fi
}

cmd_test() {
  echo "🧪 Running Learning System v2 Tests..."
  local pass=0 fail=0
  
  # Setup test environment
  local test_dir=$(mktemp -d)
  local orig_learn="$LEARN_DIR"
  export LEARN_DIR="$test_dir"
  LESSONS_FILE="$test_dir/lessons.json"
  METRICS_FILE="$test_dir/metrics.json"
  SCORES_FILE="$test_dir/scores.json"
  QUALITY_FILE="$test_dir/quality.json"
  ALERTS_FILE="$test_dir/alerts.json"
  TASK_LOG="$test_dir/task_log.json"
  
  # Init files
  echo '{"version":2,"lessons":[]}' > "$LESSONS_FILE"
  echo '{"tasks":[],"agent_stats":{}}' > "$METRICS_FILE"
  echo '{"version":1,"agents":{}}' > "$SCORES_FILE"
  echo '{"reviews":[],"agentAverages":{}}' > "$QUALITY_FILE"
  echo '{}' > "$ALERTS_FILE"
  echo '[]' > "$TASK_LOG"
  
  _test() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
      echo "  ✅ $name"
      pass=$((pass + 1))
    else
      echo "  ❌ $name (expected '$expected', got '$actual')"
      fail=$((fail + 1))
    fi
  }
  
  # Test 1: save
  local out
  out=$(cmd_save "test_agent" "task1" "pass" "test lesson 1")
  _test "save lesson" "Saved lesson" "$out"
  
  # Test 2: lesson exists
  local count
  count=$(jq '.lessons | length' "$LESSONS_FILE")
  _test "lesson stored" "1" "$count"
  
  # Test 3: record with full options
  out=$(cmd_record "test_agent" "task2" "fail" --category "code_error" --reason "syntax bug" --duration "120" --retry "2" --quality "4" --lint-errors "3")
  _test "record task" "Recorded" "$out"
  
  # Test 4: metrics stored
  count=$(jq '.tasks | length' "$METRICS_FILE")
  _test "metrics stored" "2" "$count"
  
  # Test 5: failure category
  local cat
  cat=$(jq -r '.tasks[1].category' "$METRICS_FILE")
  _test "failure category" "code_error" "$cat"
  
  # Test 6: auto lesson from failure
  count=$(jq '.lessons | length' "$LESSONS_FILE")
  _test "auto lesson from fail" "2" "$count"
  
  # Test 7: scores updated
  local score
  score=$(jq -r '.agents.test_agent.tasks' "$SCORES_FILE")
  _test "scores updated" "2" "$score"
  
  # Test 8: quality stored
  count=$(jq '.reviews | length' "$QUALITY_FILE")
  _test "quality stored" "1" "$count"
  
  # Test 9: query
  out=$(cmd_query "syntax")
  _test "query finds lesson" "syntax" "$out"
  
  # Test 10: inject
  out=$(cmd_inject "test_agent" "fix a syntax error in code")
  _test "inject returns lessons" "Lessons" "$out"
  
  # Test 11: start/end timer
  cmd_start "test_agent" "task3" > /dev/null
  sleep 1
  out=$(cmd_end "test_agent" "task3" "pass" "timer test")
  _test "timer works" "Duration:" "$out"
  
  # Test 12: agent report
  out=$(cmd_agent "test_agent")
  _test "agent report" "Agent Report" "$out"
  
  # Test 13: dashboard
  out=$(cmd_dashboard)
  _test "dashboard renders" "Dashboard" "$out"
  
  # Test 14: stats
  out=$(cmd_stats)
  _test "stats work" "Quick Stats" "$out"
  
  # Test 15: trends
  out=$(cmd_trends)
  _test "trends work" "Trends" "$out"
  
  # Test 16: why-fail
  out=$(cmd_why_fail "task2")
  _test "why-fail works" "Failure Analysis" "$out"
  
  # Test 17: export
  out=$(cmd_export "test_agent")
  _test "export works" "test_agent" "$out"
  
  # Test 18: effectiveness
  out=$(cmd_effectiveness)
  _test "effectiveness works" "Effectiveness" "$out"
  
  # Test 19: check-drift
  out=$(cmd_check_drift)
  _test "drift check works" "drift" "$out"
  
  # Test 20: auto-categorize
  out=$(cmd_record "test_agent" "task4" "fail" --reason "connection timed out waiting")
  cat=$(jq -r '.tasks[-1].category' "$METRICS_FILE")
  _test "auto-categorize timeout" "timeout" "$cat"
  
  # Cleanup
  rm -rf "$test_dir"
  LEARN_DIR="$orig_learn"
  LESSONS_FILE="$orig_learn/lessons.json"
  METRICS_FILE="$orig_learn/metrics.json"
  SCORES_FILE="$orig_learn/scores.json"
  QUALITY_FILE="$orig_learn/quality.json"
  ALERTS_FILE="$orig_learn/alerts.json"
  TASK_LOG="$orig_learn/task_log.json"
  
  echo ""
  echo "Results: $pass passed, $fail failed out of $((pass + fail)) tests"
  [[ "$fail" -gt 0 ]] && return 1 || return 0
}

# ── Main ─────────────────────────────────────────────────
CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
  save)           cmd_save "$@" ;;
  record)         cmd_record "$@" ;;
  start)          cmd_start "$@" ;;
  end)            cmd_end "$@" ;;
  query)          cmd_query "$@" ;;
  inject)         cmd_inject "$@" ;;
  why-fail)       cmd_why_fail "$@" ;;
  agent)          cmd_agent "$@" ;;
  dashboard)      cmd_dashboard ;;
  trends)         cmd_trends "$@" ;;
  stats)          cmd_stats ;;
  check-drift)    cmd_check_drift ;;
  effectiveness)  cmd_effectiveness ;;
  export)         cmd_export "$@" ;;
  test)           cmd_test ;;
  help|--help|-h) usage ;;
  *)              echo "Unknown command: $CMD"; usage; exit 1 ;;
esac
