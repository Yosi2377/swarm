// Tests for failure-taxonomy.js and smart-retry.js

const assert = require('assert');
const { classifyFailure, getRetryStrategy, buildRetryPrompt, shouldEscalate } = require('../failure-taxonomy');
const { handleFailure, retryWithContext, escalateToHuman, clearHistory } = require('../smart-retry');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ❌ ${name}: ${e.message}`);
  }
}

console.log('\n🧪 Failure Taxonomy Tests\n');

// --- Classification tests ---

console.log('Classification:');

test('build_failure: syntax error', () => {
  const r = classifyFailure({ reason: 'SyntaxError: Unexpected token' }, {}, '');
  assert.strictEqual(r.category, 'build_failure');
});

test('build_failure: cannot find module', () => {
  const r = classifyFailure({ reason: 'Cannot find module ./foo' }, {}, '');
  assert.strictEqual(r.category, 'build_failure');
});

test('auth_failure: 401', () => {
  const r = classifyFailure({ reason: 'Request failed: 401 Unauthorized' }, {}, '');
  assert.strictEqual(r.category, 'auth_failure');
});

test('auth_failure: permission denied', () => {
  const r = classifyFailure({ reason: 'Permission denied' }, {}, '');
  assert.strictEqual(r.category, 'auth_failure');
});

test('test_failure: assertion error', () => {
  const r = classifyFailure({ reason: 'AssertionError: expected true to equal false' }, {}, '');
  assert.strictEqual(r.category, 'test_failure');
});

test('timeout: timed out', () => {
  const r = classifyFailure({ reason: 'Agent timed out after 300s' }, {}, '');
  assert.strictEqual(r.category, 'timeout');
});

test('missing_requirement: unclear', () => {
  const r = classifyFailure({ reason: 'Task is unclear, need clarification' }, {}, '');
  assert.strictEqual(r.category, 'missing_requirement');
});

test('partial_implementation: criteria partially met', () => {
  const r = classifyFailure({
    reason: 'Not all criteria met',
    criteriaResults: [
      { passed: true, description: 'File created' },
      { passed: false, description: 'Tests pass' },
      { passed: false, description: 'Docs updated' },
    ]
  }, {}, '');
  assert.strictEqual(r.category, 'partial_implementation');
  assert.ok(r.details.includes('Tests pass'));
  assert.ok(r.details.includes('Docs updated'));
});

test('flaky_test: intermittent', () => {
  const r = classifyFailure({ reason: 'Flaky test: timing issue' }, {}, '');
  assert.strictEqual(r.category, 'flaky_test');
});

test('dependency_failure: connection refused', () => {
  const r = classifyFailure({ reason: 'ECONNREFUSED 127.0.0.1:5432' }, {}, '');
  assert.strictEqual(r.category, 'dependency_failure');
});

test('regression: broke something', () => {
  const r = classifyFailure({ reason: 'Regression: login was working, now broken' }, {}, '');
  assert.strictEqual(r.category, 'regression');
});

test('classifies from agentOutput too', () => {
  const r = classifyFailure({}, {}, 'Error: Permission denied for resource');
  assert.strictEqual(r.category, 'auth_failure');
});

// --- Retry strategy tests ---

console.log('\nRetry Strategies:');

test('auth_failure: never retry', () => {
  const s = getRetryStrategy('auth_failure');
  assert.strictEqual(s.shouldRetry, false);
  assert.strictEqual(s.maxRetries, 0);
});

test('missing_requirement: never retry', () => {
  const s = getRetryStrategy('missing_requirement');
  assert.strictEqual(s.shouldRetry, false);
});

test('build_failure: retry up to 3', () => {
  const s = getRetryStrategy('build_failure');
  assert.strictEqual(s.shouldRetry, true);
  assert.strictEqual(s.maxRetries, 3);
});

test('flaky_test: retry up to 3', () => {
  const s = getRetryStrategy('flaky_test');
  assert.strictEqual(s.shouldRetry, true);
  assert.strictEqual(s.maxRetries, 3);
});

test('dependency_failure: long delay', () => {
  const s = getRetryStrategy('dependency_failure');
  assert.ok(s.delayMs >= 10000);
});

test('unknown category: no retry', () => {
  const s = getRetryStrategy('totally_unknown');
  assert.strictEqual(s.shouldRetry, false);
});

// --- Retry prompt tests ---

console.log('\nRetry Prompts:');

test('partial_implementation gets "finish" prompt', () => {
  const prompt = buildRetryPrompt('Add login + signup', {
    category: 'partial_implementation',
    details: 'Missing: signup endpoint, tests',
  }, 2);
  assert.ok(prompt.includes('Retry Attempt 2'));
  assert.ok(prompt.includes('Finish these remaining items'));
  assert.ok(prompt.includes('signup endpoint'));
});

test('regression gets "also fix" prompt', () => {
  const prompt = buildRetryPrompt('Refactor auth', {
    category: 'regression',
    details: 'Regression detected: login broken',
  }, 1);
  assert.ok(prompt.includes('also fix'));
  assert.ok(prompt.includes('login broken'));
});

test('build_failure prompt includes error', () => {
  const prompt = buildRetryPrompt('Fix API', {
    category: 'build_failure',
    details: 'SyntaxError line 42',
  }, 1);
  assert.ok(prompt.includes('SyntaxError'));
  assert.ok(prompt.includes('build/compilation errors'));
});

// --- Escalation tests ---

console.log('\nEscalation:');

test('auth_failure escalates immediately', () => {
  const r = shouldEscalate([{ category: 'auth_failure', details: '401' }]);
  assert.strictEqual(r.escalate, true);
});

test('missing_requirement escalates immediately', () => {
  const r = shouldEscalate([{ category: 'missing_requirement', details: 'unclear' }]);
  assert.strictEqual(r.escalate, true);
});

test('single build_failure does not escalate', () => {
  const r = shouldEscalate([{ category: 'build_failure', details: 'err' }]);
  assert.strictEqual(r.escalate, false);
});

test('3 build_failures triggers escalation', () => {
  const history = Array(3).fill({ category: 'build_failure', details: 'err' });
  const r = shouldEscalate(history);
  assert.strictEqual(r.escalate, true);
});

test('empty history: no escalation', () => {
  const r = shouldEscalate([]);
  assert.strictEqual(r.escalate, false);
});

// --- Smart retry integration ---

console.log('\nSmart Retry Integration:');

test('handleFailure returns retry for build error', () => {
  clearHistory('test-1');
  const r = handleFailure('test-1', { reason: 'SyntaxError: bad code' }, {}, '');
  assert.strictEqual(r.action, 'retry');
  assert.strictEqual(r.failureInfo.category, 'build_failure');
});

test('handleFailure returns escalate for auth error', () => {
  clearHistory('test-2');
  const r = handleFailure('test-2', { reason: '401 Unauthorized' }, {}, '');
  assert.strictEqual(r.action, 'escalate');
});

test('retryWithContext builds enriched prompt', () => {
  clearHistory('test-3');
  handleFailure('test-3', { reason: 'Test failed: expect(1).toBe(2)' }, {}, '');
  const ctx = retryWithContext('test-3', 'Fix the calculator');
  assert.ok(ctx.prompt.includes('Fix the calculator'));
  assert.ok(ctx.prompt.includes('test_failure'));
  assert.strictEqual(ctx.attempt, 1);
});

test('escalateToHuman formats message', () => {
  clearHistory('test-4');
  handleFailure('test-4', { reason: 'Permission denied' }, {}, '');
  const msg = escalateToHuman('test-4', 'Auth failure');
  assert.ok(msg.includes('test-4'));
  assert.ok(msg.includes('auth_failure'));
  assert.ok(msg.includes('human intervention'));
});

// --- Summary ---

console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
