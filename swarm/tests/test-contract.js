// Unit tests for Task Contract Schema
const { createContract, inferContract, validateContract, enrichContract, TASK_TYPES } = require('../core/task-contract');
const { getAllTemplates } = require('../core/contract-templates');

let passed = 0, failed = 0;
function assert(condition, msg) {
  if (condition) { passed++; console.log(`  ✅ ${msg}`); }
  else { failed++; console.error(`  ❌ ${msg}`); }
}

// --- createContract ---
console.log('\n🔧 createContract');
{
  const c = createContract('code_fix', 'fix login bug');
  assert(c.id && c.id.startsWith('tc-'), 'generates id with tc- prefix');
  assert(c.type === 'code_fix', 'type is code_fix');
  assert(c.input.description === 'fix login bug', 'description set');
  assert(Array.isArray(c.acceptance_criteria) && c.acceptance_criteria.length > 0, 'has acceptance criteria');
  assert(c.rollback && c.rollback.strategy, 'has rollback strategy');
  assert(c.metadata && c.metadata.priority, 'has priority');
  const v = validateContract(c);
  assert(v.valid, 'created contract passes validation');
}

// --- inferContract (Hebrew) ---
console.log('\n🔍 inferContract');
{
  const c = inferContract('תתקן את כפתור ההתחברות');
  // "כפתור" = button → ui_change, or "תתקן" = fix → code_fix
  assert(['code_fix', 'ui_change'].includes(c.type), `inferred type=${c.type} for Hebrew fix/button`);
  assert(c.input.description === 'תתקן את כפתור ההתחברות', 'description preserved');

  const c2 = inferContract('add new user registration feature');
  assert(c2.type === 'feature', 'inferred feature from English');

  const c3 = inferContract('fix the XSS vulnerability in login');
  assert(c3.type === 'security_fix', 'inferred security_fix');

  const c4 = inferContract('migrate users table to new schema');
  assert(c4.type === 'db_migration', 'inferred db_migration');
}

// --- validateContract errors ---
console.log('\n⚠️ validateContract');
{
  const v1 = validateContract({});
  assert(!v1.valid, 'empty object is invalid');
  assert(v1.errors.length > 0, 'returns specific errors');
  assert(v1.errors.some(e => e.includes('id')), 'mentions missing id');
  assert(v1.errors.some(e => e.includes('type')), 'mentions missing type');
  assert(v1.errors.some(e => e.includes('input')), 'mentions missing input');

  const v2 = validateContract({ id: 'x', type: 'banana', input: { description: 'y' },
    expected_artifacts: { files_changed: [] }, acceptance_criteria: [{ type: 'a', description: 'b' }],
    rollback: { strategy: 'git_revert' }, metadata: { priority: 'low' } });
  assert(!v2.valid, 'invalid type rejected');
  assert(v2.errors.some(e => e.includes('banana')), 'error mentions invalid type name');

  const v3 = validateContract(null);
  assert(!v3.valid, 'null rejected');
}

// --- All templates valid ---
console.log('\n📋 Template validation');
{
  const templates = getAllTemplates();
  for (const type of TASK_TYPES) {
    assert(templates[type], `template exists for ${type}`);
    const c = createContract(type, `test ${type}`);
    const v = validateContract(c);
    assert(v.valid, `${type} template produces valid contract`);
  }
}

// --- enrichContract ---
console.log('\n🔄 enrichContract');
{
  const c = createContract('feature', 'add search');
  const e = enrichContract(c, { basePath: '/app', testCommand: 'npm test', priority: 'critical' });
  assert(e.input.context.includes('/app'), 'context enriched with basePath');
  assert(e.metadata.priority === 'critical', 'priority overridden');
  assert(e.acceptance_criteria.length > c.acceptance_criteria.length, 'test command added to criteria');
}

// --- Summary ---
console.log(`\n${'='.repeat(40)}`);
console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
