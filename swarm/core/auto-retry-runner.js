// Auto-Retry Runner — handles agent completion with automatic verify → retry loop

const fs = require('fs');
const path = require('path');
const { onAgentDone } = require('./orchestrator-bridge');
const { retryWithContext, escalateToHuman } = require('./smart-retry');
const { TASKS_DIR } = require('./task-runner');

const DONE_DIR = '/tmp/agent-done';
const RETRY_DIR = '/tmp';
const ESCALATE_DIR = '/tmp';

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function loadJson(p) {
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

/**
 * Called when done-marker detected. Runs full verify → retry loop.
 * @param {string} agentId
 * @param {string} threadId
 * @param {object} options - { context, maxRetries }
 * @returns {{ action: 'pass'|'retry'|'escalate', ... }}
 */
async function handleAgentCompletion(agentId, threadId, options = {}) {
  const taskId = `${agentId}-${threadId}`;
  const context = options.context || {};

  // 1. Run orchestrator-bridge verification (loads contract, runs semantic verify)
  const result = onAgentDone(agentId, threadId, context);

  // 2. If PASS → mark as verified
  if (result.action === 'pass') {
    const metaPath = path.join(TASKS_DIR, `${taskId}.json`);
    const meta = loadJson(metaPath);
    if (meta) {
      meta.status = 'passed';
      meta.verified_at = new Date().toISOString();
      meta.auto_verified = true;
      fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
    }
    // Remove from done queue
    const donePath = path.join(DONE_DIR, `${taskId}.json`);
    if (fs.existsSync(donePath)) {
      const done = loadJson(donePath);
      if (done) { done.verified = true; fs.writeFileSync(donePath, JSON.stringify(done, null, 2)); }
    }
    return { action: 'pass', taskId, score: result.score, checks: result.checks };
  }

  // 3. If RETRY → build retry prompt and create retry request
  if (result.action === 'retry') {
    const attempt = result.attempt || 1;
    const prompt = result.prompt || `Retry task ${taskId}: fix failing checks`;

    // Write retry prompt
    ensureDir(TASKS_DIR);
    const promptPath = path.join(TASKS_DIR, `${taskId}.retry-prompt.txt`);
    fs.writeFileSync(promptPath, prompt);

    // Create retry request
    const retryRequest = {
      agentId,
      threadId,
      taskId,
      prompt,
      attempt,
      delayMs: result.delayMs || 1000,
      failureCategory: result.failureCategory || 'unknown',
      createdAt: new Date().toISOString()
    };
    const retryPath = path.join(RETRY_DIR, `retry-request-${taskId}.json`);
    fs.writeFileSync(retryPath, JSON.stringify(retryRequest, null, 2));

    return { action: 'retry', taskId, prompt, attempt, delayMs: retryRequest.delayMs };
  }

  // 4. ESCALATE
  const reason = result.reason || 'Verification failed — non-retryable';
  const humanMessage = result.humanMessage || escalateToHuman(taskId, reason);

  const escalation = {
    agentId,
    threadId,
    taskId,
    reason,
    humanMessage,
    createdAt: new Date().toISOString()
  };
  const escalatePath = path.join(ESCALATE_DIR, `escalate-${taskId}.json`);
  fs.writeFileSync(escalatePath, JSON.stringify(escalation, null, 2));

  return { action: 'escalate', taskId, reason, humanMessage };
}

module.exports = { handleAgentCompletion };
