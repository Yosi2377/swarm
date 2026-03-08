// Task Runner — orchestrates task execution using state machine + contract

const fs = require('fs');
const path = require('path');
const { createTaskState, transition, canTransition, isTerminal, getRetryCount } = require('./state-machine');

const TASKS_DIR = '/tmp/agent-tasks';

function ensureDir() {
  if (!fs.existsSync(TASKS_DIR)) fs.mkdirSync(TASKS_DIR, { recursive: true });
}

function taskPath(taskId) {
  return path.join(TASKS_DIR, `${taskId}.json`);
}

function saveState(state) {
  ensureDir();
  fs.writeFileSync(taskPath(state.taskId), JSON.stringify(state, null, 2));
}

function loadState(taskId) {
  const p = taskPath(taskId);
  if (!fs.existsSync(p)) throw new Error(`Task not found: ${taskId}`);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

/**
 * Start a new task from a contract. Creates state, persists, returns state.
 */
function runTask(contract, opts = {}) {
  if (!contract || !contract.id) throw new Error('Invalid contract: missing id');
  const state = createTaskState(contract.id, contract, opts);
  saveState(state);
  return state;
}

/**
 * Advance a task to a new status.
 */
function advanceTask(taskId, newStatus, reason = '') {
  let state = loadState(taskId);
  state = transition(state, newStatus, reason);
  saveState(state);
  return state;
}

/**
 * Evaluate verification results against contract acceptance criteria.
 */
function onVerify(taskId, results = {}) {
  let state = loadState(taskId);
  if (state.status !== 'verifying') {
    throw new Error(`Cannot verify task in status "${state.status}" — must be "verifying"`);
  }

  const passed = results.passed ?? false;

  if (passed) {
    state = transition(state, 'passed', results.reason || 'All acceptance criteria met');
  } else {
    // Let state machine decide retryable vs terminal based on retry count
    state = transition(state, 'failed_retryable', results.reason || 'Verification failed');
  }

  saveState(state);
  return state;
}

/**
 * Retry a failed task — transitions from failed_retryable to running.
 */
function onRetry(taskId, failureInfo = {}) {
  let state = loadState(taskId);
  if (state.status !== 'failed_retryable') {
    throw new Error(`Cannot retry task in status "${state.status}" — must be "failed_retryable"`);
  }
  const reason = failureInfo.reason || `Retry #${getRetryCount(state) + 1}`;
  state = transition(state, 'running', reason);
  saveState(state);
  return state;
}

/**
 * Get all non-terminal tasks.
 */
function getActiveTasks() {
  ensureDir();
  const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.json'));
  const active = [];
  for (const f of files) {
    try {
      const state = JSON.parse(fs.readFileSync(path.join(TASKS_DIR, f), 'utf8'));
      if (!isTerminal(state)) active.push(state);
    } catch (_) { /* skip corrupt */ }
  }
  return active;
}

/**
 * Get task state by id.
 */
function getTask(taskId) {
  return loadState(taskId);
}

module.exports = { runTask, advanceTask, onVerify, onRetry, getActiveTasks, getTask, TASKS_DIR };
