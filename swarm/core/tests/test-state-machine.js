// Tests for state-machine.js and task-runner.js

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const sm = require('../state-machine');
const runner = require('../task-runner');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log(`  ✅ ${name}`); }
  catch (e) { failed++; console.log(`  ❌ ${name}: ${e.message}`); }
}

// Clean task dir before tests
const TASKS_DIR = runner.TASKS_DIR;
if (fs.existsSync(TASKS_DIR)) fs.rmSync(TASKS_DIR, { recursive: true });

const mockContract = { id: 'test-001', type: 'code_fix', input: { description: 'fix bug' }, acceptance_criteria: [] };

console.log('\n=== State Machine Tests ===');

test('createTaskState returns queued', () => {
  const s = sm.createTaskState('t1', mockContract);
  assert.strictEqual(s.status, 'queued');
  assert.strictEqual(s.taskId, 't1');
  assert.strictEqual(s.retryCount, 0);
  assert.strictEqual(s.history.length, 1);
});

test('valid transition: queued → assigned', () => {
  let s = sm.createTaskState('t2', mockContract);
  s = sm.transition(s, 'assigned', 'agent picked up');
  assert.strictEqual(s.status, 'assigned');
});

test('full happy path: queued → assigned → running → verifying → passed', () => {
  let s = sm.createTaskState('t3', mockContract);
  s = sm.transition(s, 'assigned', 'go');
  s = sm.transition(s, 'running', 'start');
  s = sm.transition(s, 'verifying', 'done coding');
  s = sm.transition(s, 'passed', 'all green');
  assert.strictEqual(s.status, 'passed');
  assert.strictEqual(s.history.length, 5);
});

test('invalid transition throws', () => {
  let s = sm.createTaskState('t4', mockContract);
  assert.throws(() => sm.transition(s, 'running'), /Invalid transition/);
});

test('invalid transition: passed → running throws', () => {
  let s = sm.createTaskState('t5', mockContract);
  s = sm.transition(s, 'assigned');
  s = sm.transition(s, 'running');
  s = sm.transition(s, 'verifying');
  s = sm.transition(s, 'passed');
  assert.throws(() => sm.transition(s, 'running'), /Invalid transition/);
});

test('retry path: verifying → failed_retryable → running', () => {
  let s = sm.createTaskState('t6', mockContract);
  s = sm.transition(s, 'assigned');
  s = sm.transition(s, 'running');
  s = sm.transition(s, 'verifying');
  s = sm.transition(s, 'failed_retryable', 'tests failed');
  assert.strictEqual(s.retryCount, 1);
  s = sm.transition(s, 'running', 'retry');
  assert.strictEqual(s.status, 'running');
});

test('retry count increments correctly', () => {
  let s = sm.createTaskState('t7', mockContract, { maxRetries: 5 });
  s = sm.transition(s, 'assigned');
  s = sm.transition(s, 'running');
  s = sm.transition(s, 'verifying');
  s = sm.transition(s, 'failed_retryable', 'fail 1');
  assert.strictEqual(sm.getRetryCount(s), 1);
  s = sm.transition(s, 'running', 'retry 1');
  s = sm.transition(s, 'verifying');
  s = sm.transition(s, 'failed_retryable', 'fail 2');
  assert.strictEqual(sm.getRetryCount(s), 2);
  s = sm.transition(s, 'running', 'retry 2');
  s = sm.transition(s, 'verifying');
  s = sm.transition(s, 'failed_retryable', 'fail 3');
  assert.strictEqual(sm.getRetryCount(s), 3);
});

test('max retries auto-escalates to failed_terminal', () => {
  let s = sm.createTaskState('t8', mockContract, { maxRetries: 2 });
  s = sm.transition(s, 'assigned');
  s = sm.transition(s, 'running');
  s = sm.transition(s, 'verifying');
  s = sm.transition(s, 'failed_retryable', 'fail 1');
  assert.strictEqual(s.retryCount, 1);
  s = sm.transition(s, 'running', 'retry');
  s = sm.transition(s, 'verifying');
  // This should auto-escalate since retryCount will be 2 == maxRetries
  s = sm.transition(s, 'failed_retryable', 'fail 2');
  assert.strictEqual(s.status, 'failed_terminal');
  assert.ok(s.history[s.history.length - 1].reason.includes('auto-escalated'));
});

test('any state → cancelled works', () => {
  for (const from of ['queued', 'assigned', 'running', 'verifying', 'failed_retryable']) {
    assert.ok(sm.canTransition({ status: from }, 'cancelled'));
  }
});

test('cancelled has no transitions out', () => {
  let s = sm.createTaskState('t9', mockContract);
  s = sm.transition(s, 'cancelled', 'abort');
  assert.throws(() => sm.transition(s, 'queued'), /Invalid transition/);
});

test('isTerminal works', () => {
  assert.ok(sm.isTerminal({ status: 'passed' }));
  assert.ok(sm.isTerminal({ status: 'failed_terminal' }));
  assert.ok(sm.isTerminal({ status: 'cancelled' }));
  assert.ok(!sm.isTerminal({ status: 'running' }));
});

test('history tracks timestamps', () => {
  let s = sm.createTaskState('t10', mockContract);
  s = sm.transition(s, 'assigned', 'go');
  for (const h of sm.getHistory(s)) {
    assert.ok(typeof h.timestamp === 'number');
    assert.ok(h.timestamp > 0);
  }
});

test('canTransition returns false for invalid', () => {
  assert.ok(!sm.canTransition({ status: 'queued' }, 'passed'));
  assert.ok(!sm.canTransition({ status: 'queued' }, 'bogus'));
});

console.log('\n=== Task Runner Tests ===');

test('runTask creates and persists state', () => {
  const s = runner.runTask(mockContract);
  assert.strictEqual(s.status, 'queued');
  assert.ok(fs.existsSync(path.join(TASKS_DIR, `${mockContract.id}.json`)));
});

test('advanceTask transitions and persists', () => {
  const s = runner.runTask({ id: 'run-001', type: 'code_fix' });
  const s2 = runner.advanceTask('run-001', 'assigned', 'picked');
  assert.strictEqual(s2.status, 'assigned');
  const loaded = runner.getTask('run-001');
  assert.strictEqual(loaded.status, 'assigned');
});

test('onVerify passes', () => {
  runner.runTask({ id: 'v-001', type: 'code_fix' });
  runner.advanceTask('v-001', 'assigned');
  runner.advanceTask('v-001', 'running');
  runner.advanceTask('v-001', 'verifying');
  const s = runner.onVerify('v-001', { passed: true, reason: 'tests pass' });
  assert.strictEqual(s.status, 'passed');
});

test('onVerify fails → retryable', () => {
  runner.runTask({ id: 'v-002', type: 'code_fix' });
  runner.advanceTask('v-002', 'assigned');
  runner.advanceTask('v-002', 'running');
  runner.advanceTask('v-002', 'verifying');
  const s = runner.onVerify('v-002', { passed: false, reason: 'lint errors' });
  assert.strictEqual(s.status, 'failed_retryable');
});

test('onRetry transitions to running', () => {
  const s = runner.onRetry('v-002', { reason: 'fixing lint' });
  assert.strictEqual(s.status, 'running');
});

test('getActiveTasks returns non-terminal only', () => {
  const active = runner.getActiveTasks();
  for (const t of active) {
    assert.ok(!sm.isTerminal(t));
  }
});

test('runTask rejects invalid contract', () => {
  assert.throws(() => runner.runTask(null), /Invalid contract/);
  assert.throws(() => runner.runTask({}), /Invalid contract/);
});

test('integration: contract + state machine full lifecycle', () => {
  const contract = { id: 'integ-001', type: 'feature', acceptance_criteria: [{ type: 'test_pass' }] };
  runner.runTask(contract, { maxRetries: 2 });
  runner.advanceTask('integ-001', 'assigned', 'koder');
  runner.advanceTask('integ-001', 'running', 'coding');
  runner.advanceTask('integ-001', 'verifying', 'ready');
  // First fail
  runner.onVerify('integ-001', { passed: false, reason: 'test fail' });
  runner.onRetry('integ-001', { reason: 'fix tests' });
  runner.advanceTask('integ-001', 'verifying', 'try 2');
  // Second fail — should auto-escalate
  const final = runner.onVerify('integ-001', { passed: false, reason: 'still failing' });
  assert.strictEqual(final.status, 'failed_terminal');
  assert.strictEqual(sm.getRetryCount(final), 2);
});

// Cleanup
if (fs.existsSync(TASKS_DIR)) fs.rmSync(TASKS_DIR, { recursive: true });

console.log(`\n✅ Passed: ${passed} | ❌ Failed: ${failed}\n`);
process.exit(failed > 0 ? 1 : 0);
