// Task State Machine — strict lifecycle management

const STATES = ['queued', 'assigned', 'running', 'verifying', 'passed', 'failed_retryable', 'failed_terminal', 'cancelled'];
const TERMINAL_STATES = ['passed', 'failed_terminal', 'cancelled'];

const VALID_TRANSITIONS = {
  queued:             ['assigned', 'cancelled'],
  assigned:           ['running', 'cancelled'],
  running:            ['verifying', 'cancelled'],
  verifying:          ['passed', 'failed_retryable', 'failed_terminal', 'cancelled'],
  failed_retryable:   ['running', 'cancelled'],
  // terminal — no transitions out (except forced)
  passed:             ['cancelled'],
  failed_terminal:    ['cancelled'],
  cancelled:          [],
};

const DEFAULT_MAX_RETRIES = 3;

function createTaskState(taskId, contract, opts = {}) {
  const now = Date.now();
  return {
    taskId,
    contractId: contract?.id || null,
    status: 'queued',
    retryCount: 0,
    maxRetries: opts.maxRetries ?? DEFAULT_MAX_RETRIES,
    history: [{ from: null, to: 'queued', reason: 'created', timestamp: now }],
    createdAt: now,
    updatedAt: now,
  };
}

function canTransition(state, newStatus) {
  if (!STATES.includes(newStatus)) return false;
  const allowed = VALID_TRANSITIONS[state.status];
  return allowed ? allowed.includes(newStatus) : false;
}

function transition(state, newStatus, reason = '') {
  if (!canTransition(state, newStatus)) {
    throw new Error(`Invalid transition: ${state.status} → ${newStatus} (task ${state.taskId})`);
  }

  const now = Date.now();
  const prev = state.status;

  const updated = { ...state };

  // Track retries and auto-escalate
  if (newStatus === 'failed_retryable') {
    updated.retryCount = state.retryCount + 1;
    if (updated.retryCount >= state.maxRetries) {
      newStatus = 'failed_terminal';
      reason = `${reason} [auto-escalated: max retries (${state.maxRetries}) reached]`.trim();
    }
  }

  updated.status = newStatus;
  updated.updatedAt = now;
  updated.history = [...state.history, { from: prev, to: newStatus, reason, timestamp: now }];

  return updated;
}

function getHistory(state) {
  return state.history;
}

function isTerminal(state) {
  return TERMINAL_STATES.includes(state.status);
}

function getRetryCount(state) {
  return state.retryCount;
}

module.exports = {
  STATES,
  TERMINAL_STATES,
  VALID_TRANSITIONS,
  DEFAULT_MAX_RETRIES,
  createTaskState,
  transition,
  canTransition,
  getHistory,
  isTerminal,
  getRetryCount,
};
