// Watchdog — detects stuck agents and creates retry requests

const fs = require('fs');
const path = require('path');
const { hasRecentProgress, getProgressSummary } = require('./progress-tracker');

const TASKS_DIR = process.env.TASKS_DIR || '/tmp/agent-tasks';
const DONE_DIR = process.env.DONE_DIR || '/tmp/agent-done';
const RETRY_DIR = process.env.RETRY_DIR || '/tmp';
const LOG_DIR = process.env.WATCHDOG_LOG_DIR || path.resolve(__dirname, '..', 'logs');

const DEFAULT_MAX_MINUTES = parseInt(process.env.WATCHDOG_MAX_MINUTES || '10', 10);
const PROGRESS_EXTEND_MINUTES = parseInt(process.env.WATCHDOG_PROGRESS_EXTEND || '3', 10);

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function loadJson(p) {
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

function log(message) {
  ensureDir(LOG_DIR);
  const line = `[${new Date().toISOString()}] ${message}\n`;
  fs.appendFileSync(path.join(LOG_DIR, 'watchdog.log'), line);
}

/**
 * Run the watchdog check. Returns array of actions taken.
 */
function runWatchdog(options = {}) {
  const maxMinutes = options.maxMinutes || DEFAULT_MAX_MINUTES;
  const results = [];

  ensureDir(TASKS_DIR);
  ensureDir(DONE_DIR);

  const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.json') && !f.includes('.contract') && !f.includes('.retry'));

  for (const file of files) {
    const taskPath = path.join(TASKS_DIR, file);
    const meta = loadJson(taskPath);
    if (!meta) continue;

    // Check BOTH status fields
    const status = meta.task_state?.status || meta.status;
    if (!['running', 'assigned', 'queued'].includes(status)) continue;

    // If task is queued but has a started_at, treat as running (auto-fix)
    if (status === 'queued' && meta.started_at) {
      meta.status = 'running';
      if (meta.task_state) {
        const now = Date.now();
        meta.task_state.history.push({ from: meta.task_state.status, to: 'running', reason: 'auto-corrected by watchdog', timestamp: now });
        meta.task_state.status = 'running';
        meta.task_state.updatedAt = now;
      }
      fs.writeFileSync(taskPath, JSON.stringify(meta, null, 2));
    }

    const taskId = file.replace('.json', '');
    const agentId = meta.agent_id || meta.agentId || taskId.split('-')[0];
    const threadId = meta.thread_id || meta.threadId || taskId.split('-').slice(1).join('-');

    // Check if done marker exists
    const donePath = path.join(DONE_DIR, `${taskId}.json`);
    if (fs.existsSync(donePath)) continue;

    // Calculate elapsed time
    const startedAt = meta.started_at || meta.dispatched_at || meta.created;
    if (!startedAt) continue;
    const elapsedMinutes = (Date.now() - new Date(startedAt).getTime()) / 60000;

    // Check for recent progress — extends timeout
    if (hasRecentProgress(agentId, threadId, PROGRESS_EXTEND_MINUTES)) {
      results.push({ taskId, action: 'alive', reason: 'recent_progress', elapsedMinutes });
      continue;
    }

    if (elapsedMinutes < maxMinutes) continue;

    // Check idempotency — don't re-flag already flagged tasks
    if (meta.status === 'failed_retryable' && meta.watchdog_flagged) {
      results.push({ taskId, action: 'already_flagged', elapsedMinutes });
      continue;
    }

    // STUCK DETECTED
    log(`STUCK: ${taskId} running for ${Math.round(elapsedMinutes)}m (max: ${maxMinutes}m)`);

    // 1. Update task status
    meta.status = 'failed_retryable';
    meta.watchdog_flagged = true;
    meta.watchdog_flagged_at = new Date().toISOString();
    meta.failure_reason = 'stuck/timeout';
    fs.writeFileSync(taskPath, JSON.stringify(meta, null, 2));

    // 2. Create retry request (only if one doesn't exist)
    const retryPath = path.join(RETRY_DIR, `retry-request-${agentId}-${threadId}.json`);
    if (!fs.existsSync(retryPath)) {
      const progressSummary = getProgressSummary(agentId, threadId);
      const retryRequest = {
        agentId,
        threadId,
        taskId,
        reason: 'stuck/timeout',
        elapsedMinutes: Math.round(elapsedMinutes),
        progressSummary,
        originalTask: meta.task_desc || meta.description || '',
        retryCount: (meta.retries || 0) + 1,
        createdAt: new Date().toISOString()
      };
      fs.writeFileSync(retryPath, JSON.stringify(retryRequest, null, 2));
      log(`RETRY REQUEST: ${retryPath}`);
    }

    // 3. Log
    log(`FLAGGED: ${taskId} → failed_retryable`);

    results.push({ taskId, action: 'flagged_stuck', elapsedMinutes: Math.round(elapsedMinutes) });
  }

  return results;
}

module.exports = { runWatchdog, log };

// CLI mode
if (require.main === module) {
  const results = runWatchdog();
  console.log(JSON.stringify({ checked: results.length, results }, null, 2));
}
