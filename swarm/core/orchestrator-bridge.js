// Orchestrator Bridge — glue connecting all reliability layer modules
// Main entry point for the orchestrator (Or) to use

const fs = require('fs');
const path = require('path');
const { inferContract, enrichContract, validateContract } = require('./task-contract');
const { createTaskState, transition, isTerminal, getRetryCount } = require('./state-machine');
const { runTask, advanceTask, TASKS_DIR } = require('./task-runner');
const { runVerification, verifyAndDecide } = require('./semantic-verify');
const { classifyFailure, buildRetryPrompt } = require('./failure-taxonomy');
const { handleFailure, retryWithContext, escalateToHuman, clearHistory } = require('./smart-retry');
const { requestHelp, respondToHelp, getPendingConsultations, getAllConsultations } = require('./agent-consultation');

const SWARM_DIR = path.resolve(__dirname, '..');

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function contractPath(agentId, threadId) {
  return path.join(TASKS_DIR, `${agentId}-${threadId}.contract.json`);
}

function statePath(agentId, threadId) {
  return path.join(TASKS_DIR, `${agentId}-${threadId}.json`);
}

function loadJson(p) {
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

/**
 * Build the agent prompt section for acceptance criteria.
 */
function buildAcceptanceCriteriaBlock(contract) {
  const lines = ['## ✅ Acceptance Criteria (Auto-Verified)', ''];
  lines.push('Your work will be automatically verified against these criteria:');
  lines.push('');
  (contract.acceptance_criteria || []).forEach((c, i) => {
    lines.push(`${i + 1}. **[${c.type}]** ${c.description}`);
  });
  lines.push('');
  lines.push('⚠️ All criteria must pass for the task to be accepted.');
  lines.push('If verification fails, you may be retried with additional context.');
  return lines.join('\n');
}

/**
 * When Or receives a task from Yossi:
 * 1. inferContract from description
 * 2. enrichContract with project config
 * 3. validateContract
 * 4. createTaskState
 * 5. Return { contract, state, agentPrompt } ready to spawn
 */
function prepareTask(taskDescription, agentId, threadId, projectConfig) {
  ensureDir(TASKS_DIR);

  // 1. Infer contract from description
  let contract = inferContract(taskDescription);

  // 2. Enrich with project config
  if (projectConfig && typeof projectConfig === 'object') {
    contract = enrichContract(contract, projectConfig);
  } else if (typeof projectConfig === 'string' && projectConfig) {
    contract = enrichContract(contract, { basePath: projectConfig });
  }

  // 3. Validate
  const validation = validateContract(contract);
  if (!validation.valid) {
    return { errors: validation.errors, contract, state: null, agentPrompt: null };
  }

  // 4. Create task state
  const taskId = `${agentId}-${threadId}`;
  const state = createTaskState(taskId, contract);

  // 5. Save contract + state
  fs.writeFileSync(contractPath(agentId, threadId), JSON.stringify(contract, null, 2));

  // Merge state into existing metadata if present
  const existingMeta = loadJson(statePath(agentId, threadId));
  const mergedState = existingMeta
    ? { ...existingMeta, contract_id: contract.id, task_state: state }
    : { agent_id: agentId, thread_id: threadId, contract_id: contract.id, task_state: state, dispatched_at: new Date().toISOString() };
  fs.writeFileSync(statePath(agentId, threadId), JSON.stringify(mergedState, null, 2));

  // Also run the task through task-runner for its own state tracking
  runTask(contract);

  // 6. Build enriched agent prompt
  const criteriaBlock = buildAcceptanceCriteriaBlock(contract);
  const agentPrompt = [
    `## Contract: ${contract.type} (${contract.id})`,
    '',
    criteriaBlock,
    '',
    `## Task Type: ${contract.type}`,
    `## Priority: ${contract.metadata.priority}`,
    contract.rollback.strategy !== 'none' ? `## Rollback: ${contract.rollback.strategy}` : '',
  ].filter(Boolean).join('\n');

  return { contract, state, agentPrompt, errors: null };
}

/**
 * When agent reports done (done-marker):
 * 1. Load contract + state
 * 2. Run semantic verification
 * 3. verifyAndDecide → pass/retry/escalate
 */
function onAgentDone(agentId, threadId, context) {
  const taskId = `${agentId}-${threadId}`;
  const contract = loadJson(contractPath(agentId, threadId));
  const metaState = loadJson(statePath(agentId, threadId));

  if (!contract) {
    // No contract = untracked task — FAIL, don't auto-pass
    return { action: 'retry', reason: 'No contract found — task was not dispatched through reliability layer. Use dispatch-task.sh to create a contract.', taskId };
  }

  const ctx = context || {};

  // Run semantic verification
  const decision = verifyAndDecide(taskId, contract, ctx);

  if (decision.verdict === 'pass') {
    if (metaState) {
      const now = Date.now();
      metaState.status = 'passed';
      metaState.verified_at = new Date().toISOString();
      if (metaState.task_state) {
        metaState.task_state.history.push({ from: metaState.task_state.status, to: 'passed', reason: 'All criteria met', timestamp: now });
        metaState.task_state.status = 'passed';
        metaState.task_state.updatedAt = now;
      }
      fs.writeFileSync(statePath(agentId, threadId), JSON.stringify(metaState, null, 2));
    }

    return {
      action: 'pass',
      taskId,
      score: decision.details.score,
      checks: decision.details.checks
    };
  }

  if (decision.verdict === 'retry') {
    // Classify and build retry prompt
    const verifyResults = { reason: decision.retryHint, criteriaResults: decision.details.checks };
    const failureResult = handleFailure(taskId, verifyResults, contract, '');

    if (failureResult.action === 'escalate') {
      const humanMessage = escalateToHuman(taskId, failureResult.reason);
      if (metaState) {
        const now = Date.now();
        metaState.status = 'failed_terminal';
        metaState.escalated_at = new Date().toISOString();
        metaState.escalation_reason = failureResult.reason;
        if (metaState.task_state) {
          metaState.task_state.history.push({ from: metaState.task_state.status, to: 'failed_terminal', reason: failureResult.reason, timestamp: now });
          metaState.task_state.status = 'failed_terminal';
          metaState.task_state.updatedAt = now;
        }
        fs.writeFileSync(statePath(agentId, threadId), JSON.stringify(metaState, null, 2));
      }
      return { action: 'escalate', taskId, reason: failureResult.reason, humanMessage };
    }

    const retryInfo = retryWithContext(taskId, contract.input.description);

    if (metaState) {
      const now = Date.now();
      metaState.status = 'retrying';
      metaState.retry_count = (metaState.retry_count || 0) + 1;
      metaState.last_failure = decision.retryHint;
      if (metaState.task_state) {
        metaState.task_state.history.push({ from: metaState.task_state.status, to: 'retrying', reason: decision.retryHint || 'Retry needed', timestamp: now });
        metaState.task_state.status = 'retrying';
        metaState.task_state.updatedAt = now;
      }
      fs.writeFileSync(statePath(agentId, threadId), JSON.stringify(metaState, null, 2));
    }

    return {
      action: 'retry',
      taskId,
      prompt: retryInfo.prompt,
      attempt: retryInfo.attempt,
      delayMs: retryInfo.delayMs,
      failureCategory: decision.failureCategory
    };
  }

  // Escalate
  const humanMessage = escalateToHuman(taskId, decision.retryHint || 'Non-retryable failure');
  if (metaState) {
    const now = Date.now();
    metaState.status = 'failed_terminal';
    metaState.escalated_at = new Date().toISOString();
    if (metaState.task_state) {
      metaState.task_state.history.push({ from: metaState.task_state.status, to: 'failed_terminal', reason: decision.retryHint || 'Non-retryable failure', timestamp: now });
      metaState.task_state.status = 'failed_terminal';
      metaState.task_state.updatedAt = now;
    }
    fs.writeFileSync(statePath(agentId, threadId), JSON.stringify(metaState, null, 2));
  }

  return {
    action: 'escalate',
    taskId,
    reason: decision.retryHint,
    humanMessage,
    failureCategory: decision.failureCategory
  };
}

/**
 * Dashboard: get status of all tasks.
 */
function getTaskDashboard() {
  ensureDir(TASKS_DIR);
  const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.json') && !f.endsWith('.contract.json'));
  const tasks = [];

  for (const f of files) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(TASKS_DIR, f), 'utf8'));
      tasks.push({
        file: f,
        agent_id: data.agent_id || data.taskId?.split('-')[0] || 'unknown',
        thread_id: data.thread_id || 'unknown',
        status: data.status || data.task_state?.status || 'unknown',
        dispatched_at: data.dispatched_at || data.createdAt,
        contract_id: data.contract_id || data.contractId || null,
        retry_count: data.retry_count || data.retryCount || 0
      });
    } catch (_) {}
  }

  const summary = {
    total: tasks.length,
    by_status: {},
    by_agent: {},
    tasks
  };

  for (const t of tasks) {
    summary.by_status[t.status] = (summary.by_status[t.status] || 0) + 1;
    summary.by_agent[t.agent_id] = (summary.by_agent[t.agent_id] || 0) + 1;
  }

  return summary;
}

/**
 * Inter-agent consultation (delegates to agent-consultation module).
 */
function requestConsultation(fromAgent, toAgent, threadId, question) {
  return requestHelp(fromAgent, toAgent, threadId, question);
}

module.exports = {
  prepareTask,
  onAgentDone,
  getTaskDashboard,
  requestConsultation,
  // Re-export for convenience
  respondToHelp,
  getPendingConsultations,
  getAllConsultations
};
