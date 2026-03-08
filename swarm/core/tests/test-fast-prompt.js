// Tests for fast-prompt

const assert = require('assert');
const { generateFastPrompt, classifyComplexity, COMPLEXITY } = require('../fast-prompt');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✅ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ❌ ${name}: ${e.message}`);
    failed++;
  }
}

console.log('\n🧪 Fast Prompt Tests\n');

const simpleContract = {
  id: 'tc-simple',
  type: 'code_fix',
  acceptance_criteria: [{ type: 'file_contains', description: 'File updated' }],
  metadata: { priority: 'normal' },
  rollback: { strategy: 'none' }
};

const complexContract = {
  id: 'tc-complex',
  type: 'feature',
  acceptance_criteria: [
    { type: 'http_status', description: 'API responds 200' },
    { type: 'test_passes', description: 'All tests pass' },
    { type: 'file_contains', description: 'New file created' },
    { type: 'db_count', description: 'DB records exist' },
    { type: 'no_regression', description: 'No regressions' },
    { type: 'custom', description: 'Service running' },
  ],
  metadata: { priority: 'high' },
  rollback: { strategy: 'git_revert' }
};

test('Simple task gets short prompt (< 500 chars)', () => {
  const result = generateFastPrompt('koder', '1234', 'Change the title color to red', simpleContract, { path: '/app' });
  assert.ok(result.isSimple, 'Should be classified as simple');
  assert.ok(result.prompt.length < 500, `Prompt too long: ${result.prompt.length} chars`);
});

test('Complex task gets full prompt', () => {
  const desc = 'Build a new user authentication system with JWT tokens, implement registration, login, password reset, and email verification';
  const result = generateFastPrompt('koder', '5678', desc, complexContract, { path: '/app', sandboxUrl: 'http://localhost:3000' });
  assert.ok(!result.isSimple, 'Should not be simple');
  assert.ok(result.prompt.length > 500, 'Complex prompt should be longer');
  assert.ok(result.prompt.includes('Contract'), 'Should include contract info');
});

test('Fast prompt includes acceptance criteria', () => {
  const result = generateFastPrompt('koder', '1234', 'Update the config file setting', simpleContract, {});
  assert.ok(result.prompt.includes('File updated'), 'Should include criterion description');
});

test('Fast prompt includes done commands', () => {
  const result = generateFastPrompt('koder', '1234', 'Fix the bug', simpleContract, {});
  assert.ok(result.prompt.includes('send.sh'), 'Should include send.sh');
  assert.ok(result.prompt.includes('done-marker.sh'), 'Should include done-marker');
});

test('classifyComplexity returns simple for trivial tasks', () => {
  assert.strictEqual(classifyComplexity('Change the title text', simpleContract), COMPLEXITY.simple);
  assert.strictEqual(classifyComplexity('Fix typo in readme', { acceptance_criteria: [] }), COMPLEXITY.simple);
});

test('classifyComplexity returns complex for big tasks', () => {
  assert.strictEqual(classifyComplexity('Build a new authentication system', complexContract), COMPLEXITY.complex);
  assert.strictEqual(classifyComplexity('Migrate the entire database architecture', complexContract), COMPLEXITY.complex);
});

test('classifyComplexity returns medium for mid-range tasks', () => {
  const medContract = { acceptance_criteria: [{ type: 'a' }, { type: 'b' }, { type: 'c' }], metadata: {} };
  const result = classifyComplexity('Adjust the user profile page with database fields, validation logic, and API integration across multiple services for better UX handling', medContract);
  assert.strictEqual(result, COMPLEXITY.medium);
});

console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
