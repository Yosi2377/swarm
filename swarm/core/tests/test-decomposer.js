// Tests for task-decomposer

const assert = require('assert');
const { shouldDecompose, decompose, buildDependencyGraph } = require('../task-decomposer');

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

console.log('\n🧪 Task Decomposer Tests\n');

test('"Add X and fix Y" decomposes into 2 subtasks', () => {
  const desc = 'Add a new login page and fix the broken navbar styling';
  assert.ok(shouldDecompose(desc));
  const subtasks = decompose(desc);
  assert.strictEqual(subtasks.length, 2);
  assert.ok(subtasks[0].description.includes('login') || subtasks[1].description.includes('login'));
  assert.ok(subtasks[0].description.includes('navbar') || subtasks[1].description.includes('navbar'));
});

test('"1. Do A 2. Do B 3. Do C" decomposes into 3 subtasks', () => {
  const desc = '1. Update the database schema\n2. Add new API endpoint for users\n3. Create frontend form for registration';
  assert.ok(shouldDecompose(desc));
  const subtasks = decompose(desc);
  assert.strictEqual(subtasks.length, 3);
  assert.ok(subtasks[0].description.includes('database'));
  assert.ok(subtasks[1].description.includes('API'));
  assert.ok(subtasks[2].description.includes('frontend'));
});

test('Simple single-action task does NOT decompose', () => {
  const desc = 'Fix the typo in header';
  assert.ok(!shouldDecompose(desc));
});

test('Dependency graph is correct', () => {
  const desc = '1. Update the database schema\n2. Add new API endpoint\n3. Create frontend form';
  const subtasks = decompose(desc);
  const graph = buildDependencyGraph(subtasks);
  
  assert.ok(graph.waves.length >= 1);
  assert.ok(graph.subtasks.length === 3);
  // First subtask should be in first wave
  assert.ok(graph.waves[0].includes('subtask-1'));
  assert.strictEqual(graph.totalWaves, 3); // sequential numbered list
});

test('Hebrew decomposition works', () => {
  const desc = 'תקן את הבאג בדף הבית וגם עדכן את העיצוב של הכפתורים';
  assert.ok(shouldDecompose(desc));
  const subtasks = decompose(desc);
  assert.ok(subtasks.length >= 2);
});

test('Each subtask gets its own contract', () => {
  const desc = '1. Fix the CSS bug\n2. Add new API route';
  const subtasks = decompose(desc);
  for (const st of subtasks) {
    assert.ok(st.contract, `Subtask ${st.id} should have a contract`);
    assert.ok(st.contract.id, `Contract should have an id`);
    assert.ok(st.contract.type, `Contract should have a type`);
  }
});

test('Parallel tasks have correct graph', () => {
  const subtasks = [
    { id: 'a', description: 'Task A', dependsOn: [] },
    { id: 'b', description: 'Task B', dependsOn: [] },
    { id: 'c', description: 'Task C', dependsOn: ['a', 'b'] },
  ];
  const graph = buildDependencyGraph(subtasks);
  assert.strictEqual(graph.waves.length, 2);
  assert.ok(graph.waves[0].includes('a'));
  assert.ok(graph.waves[0].includes('b'));
  assert.ok(graph.waves[1].includes('c'));
  assert.ok(graph.parallelizable);
});

console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
