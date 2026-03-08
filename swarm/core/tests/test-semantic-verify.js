// Tests for Semantic Verification Engine

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { RUNNERS, TYPE_CHECKS, runVerification, verifyAndDecide, navigateJsonPath, deepEqual } = require('../semantic-verify');

let passed = 0, failed = 0;

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

console.log('\n=== Semantic Verify Tests ===\n');

// ─── Helper tests ───

test('navigateJsonPath - simple path', () => {
  assert.strictEqual(navigateJsonPath({ a: { b: 42 } }, 'a.b'), 42);
});

test('navigateJsonPath - array index', () => {
  assert.strictEqual(navigateJsonPath({ items: [10, 20, 30] }, 'items[1]'), 20);
});

test('navigateJsonPath - null path returns obj', () => {
  const obj = { x: 1 };
  assert.deepStrictEqual(navigateJsonPath(obj, null), obj);
});

test('deepEqual - primitives', () => {
  assert(deepEqual(42, 42));
  assert(deepEqual('hello', 'hello'));
  assert(!deepEqual(1, 2));
});

test('deepEqual - string coercion', () => {
  assert(deepEqual(200, '200'));
});

// ─── file_contains ───

test('file_contains - finds pattern', () => {
  const tmpFile = '/tmp/test-sv-file.txt';
  fs.writeFileSync(tmpFile, 'hello world foo bar\nline two 12345');
  const r = RUNNERS.file_contains({ file: tmpFile, pattern: '\\d{5}' });
  assert(r.passed);
  fs.unlinkSync(tmpFile);
});

test('file_contains - pattern not found', () => {
  const tmpFile = '/tmp/test-sv-file2.txt';
  fs.writeFileSync(tmpFile, 'no numbers here');
  const r = RUNNERS.file_contains({ file: tmpFile, pattern: '\\d+' });
  assert(!r.passed);
  fs.unlinkSync(tmpFile);
});

test('file_contains - missing file', () => {
  const r = RUNNERS.file_contains({ file: '/tmp/nonexistent-sv-test', pattern: 'x' });
  assert(!r.passed);
  assert(r.error);
});

// ─── test_passes ───

test('test_passes - successful command', () => {
  const r = RUNNERS.test_passes({ command: 'echo ok' });
  assert(r.passed);
});

test('test_passes - failing command', () => {
  const r = RUNNERS.test_passes({ command: 'exit 1' });
  assert(!r.passed);
});

// ─── custom ───

test('custom - runs script', () => {
  const r = RUNNERS.custom({ script: 'true' });
  assert(r.passed);
});

test('custom - failing script', () => {
  const r = RUNNERS.custom({ script: 'false' });
  assert(!r.passed);
});

// ─── git_diff ───

test('git_diff - runs in workspace', () => {
  // Just verify it doesn't crash; result depends on git state
  const r = RUNNERS.git_diff({ cwd: '/root/.openclaw/workspace' });
  assert('passed' in r);
});

// ─── http_status (localhost, may not have server) ───

test('http_status - unreachable returns error', () => {
  const r = RUNNERS.http_status({ url: 'http://localhost:19999', expected: 200 });
  // Should fail gracefully
  assert(!r.passed || r.actual === '000');
});

// ─── runVerification ───

test('runVerification - empty criteria passes', () => {
  const r = runVerification({ acceptance_criteria: [] });
  assert(r.passed);
  assert.strictEqual(r.score, 100);
});

test('runVerification - all pass', () => {
  const contract = {
    acceptance_criteria: [
      { type: 'test_passes', command: 'true', description: 'trivial' },
      { type: 'test_passes', command: 'echo hi', description: 'echo' },
    ]
  };
  const r = runVerification(contract);
  assert(r.passed);
  assert.strictEqual(r.score, 100);
  assert.strictEqual(r.checks.length, 2);
});

test('runVerification - partial failure', () => {
  const contract = {
    acceptance_criteria: [
      { type: 'test_passes', command: 'true', description: 'pass' },
      { type: 'test_passes', command: 'false', description: 'fail' },
    ]
  };
  const r = runVerification(contract);
  assert(!r.passed);
  assert.strictEqual(r.score, 50);
});

test('runVerification - unknown type', () => {
  const contract = {
    acceptance_criteria: [{ type: 'nonexistent_type', description: 'bad' }]
  };
  const r = runVerification(contract);
  assert(!r.passed);
  assert(r.checks[0].error.includes('No runner'));
});

// ─── Typed verification ───

test('TYPE_CHECKS - code_fix adds git_diff + tests', () => {
  const checks = TYPE_CHECKS.code_fix({}, { cwd: '.', testCommand: 'npm test' });
  assert(checks.some(c => c.type === 'git_diff'));
  assert(checks.some(c => c.type === 'test_passes'));
  assert(checks.some(c => c.type === 'no_regression'));
});

test('TYPE_CHECKS - feature adds endpoint check', () => {
  const checks = TYPE_CHECKS.feature({}, { endpoint: 'http://localhost:3000' });
  assert(checks.some(c => c.type === 'http_status'));
});

test('TYPE_CHECKS - ui_change adds responsive checks', () => {
  const checks = TYPE_CHECKS.ui_change({}, { url: 'http://localhost:3000', cwd: '.' });
  const httpChecks = checks.filter(c => c.type === 'http_status');
  assert(httpChecks.length >= 3); // 3 viewports
});

test('TYPE_CHECKS - api_endpoint adds 200 and 404 checks', () => {
  const checks = TYPE_CHECKS.api_endpoint({}, { endpoint: 'http://localhost:3000/api' });
  assert.strictEqual(checks.length, 2);
});

test('TYPE_CHECKS - refactor adds tests + no_regression', () => {
  const checks = TYPE_CHECKS.refactor({}, { testCommand: 'npm test', cwd: '.' });
  assert(checks.some(c => c.type === 'no_regression'));
});

test('TYPE_CHECKS - security_fix adds scan + git_diff', () => {
  const checks = TYPE_CHECKS.security_fix({}, { scanCommand: 'npm audit', cwd: '.' });
  assert(checks.some(c => c.type === 'test_passes'));
  assert(checks.some(c => c.type === 'git_diff'));
});

// ─── Score calculation ───

test('Score - 1 of 3 passes = 33', () => {
  const contract = {
    acceptance_criteria: [
      { type: 'test_passes', command: 'true', description: 'a' },
      { type: 'test_passes', command: 'false', description: 'b' },
      { type: 'test_passes', command: 'false', description: 'c' },
    ]
  };
  const r = runVerification(contract);
  assert.strictEqual(r.score, 33);
});

// ─── verifyAndDecide ───

test('verifyAndDecide - pass verdict', () => {
  const contract = { id: 'test1', acceptance_criteria: [{ type: 'test_passes', command: 'true', description: 'ok' }] };
  const r = verifyAndDecide('t1', contract);
  assert.strictEqual(r.verdict, 'pass');
});

test('verifyAndDecide - retry verdict for test failure', () => {
  const contract = { id: 'test2', acceptance_criteria: [{ type: 'test_passes', command: 'false', description: 'fail' }] };
  const r = verifyAndDecide('t2', contract);
  assert(['retry', 'escalate'].includes(r.verdict));
  assert(r.failureCategory);
});

test('verifyAndDecide - escalate for auth failure', () => {
  const contract = { id: 'test3', acceptance_criteria: [{ type: 'test_passes', command: 'echo "permission denied" && exit 1', description: 'auth' }] };
  const r = verifyAndDecide('t3', contract);
  assert.strictEqual(r.verdict, 'escalate');
  assert.strictEqual(r.failureCategory, 'auth_failure');
});

// ─── Summary ───

console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
