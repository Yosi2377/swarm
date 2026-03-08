// Smart Retry — integrates failure taxonomy with state machine and task runner

const { classifyFailure, getRetryStrategy, buildRetryPrompt, shouldEscalate } = require('./failure-taxonomy');
const { loadState, saveState } = (() => {
  const fs = require('fs');
  const path = require('path');
  const { TASKS_DIR } = require('./task-runner');
  return {
    loadState(taskId) {
      const p = path.join(TASKS_DIR, `${taskId}.json`);
      if (!fs.existsSync(p)) throw new Error(`Task not found: ${taskId}`);
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    },
    saveState(state) {
      const dir = TASKS_DIR;
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `${state.taskId}.json`), JSON.stringify(state, null, 2));
    },
  };
})();
const { transition, getRetryCount } = require('./state-machine');

// In-memory failure history per task
const failureHistories = new Map();

function getFailureHistory(taskId) {
  return failureHistories.get(taskId) || [];
}

/**
 * Handle a task failure: classify, decide retry vs escalate, update state.
 * Returns { action: 'retry'|'escalate', failureInfo, state }
 */
function handleFailure(taskId, verifyResults, taskContract, agentOutput) {
  const failureInfo = classifyFailure(verifyResults, taskContract, agentOutput);
  const history = getFailureHistory(taskId);
  history.push(failureInfo);
  failureHistories.set(taskId, history);

  const escalation = shouldEscalate(history);

  if (escalation.escalate) {
    return {
      action: 'escalate',
      failureInfo,
      reason: escalation.reason,
      history,
    };
  }

  const strategy = getRetryStrategy(failureInfo.category);
  return {
    action: 'retry',
    failureInfo,
    strategy,
    history,
  };
}

/**
 * Build enriched prompt for retrying a failed task.
 */
function retryWithContext(taskId, originalTask) {
  const history = getFailureHistory(taskId);
  if (history.length === 0) {
    throw new Error(`No failure history for task ${taskId}`);
  }

  const latestFailure = history[history.length - 1];
  const attempt = history.length;
  const strategy = getRetryStrategy(latestFailure.category);

  return {
    prompt: buildRetryPrompt(originalTask, latestFailure, attempt),
    delayMs: strategy.delayMs,
    attempt,
  };
}

/**
 * Format an escalation message for humans.
 */
function escalateToHuman(taskId, reason) {
  const history = getFailureHistory(taskId);
  const categories = history.map(h => h.category);

  const lines = [
    `🚨 Task ${taskId} requires human intervention`,
    ``,
    `**Reason:** ${reason}`,
    `**Attempts:** ${history.length}`,
    `**Failure types:** ${[...new Set(categories)].join(', ')}`,
    ``,
    `**Failure details:**`,
  ];

  history.forEach((h, i) => {
    lines.push(`  ${i + 1}. [${h.category}] ${h.details}`);
  });

  return lines.join('\n');
}

/**
 * Clear failure history for a task (e.g., after manual resolution).
 */
function clearHistory(taskId) {
  failureHistories.delete(taskId);
}

module.exports = {
  handleFailure,
  retryWithContext,
  escalateToHuman,
  clearHistory,
  getFailureHistory,
};
