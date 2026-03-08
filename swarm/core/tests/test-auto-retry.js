// Tests for auto-retry-runner

const assert = require('assert');
const fs = require('fs');
const path = require('path');

// Setup: mock /tmp/agent-tasks with a test contract
const TASKS_DIR = '/tmp/agent-tasks';
if (!fs.existsSync(TASKS_DIR)) fs.mkdirSync(TASKS_DIR, { recursive: true });

// Create a simple passing contract (no criteria = auto-pass)
const passContract = {
  id: 'tc-test-pass',
  type: 'code_fix',
  input: { description: 'Fix a small bug' },
  acceptance_criteria: [],
  rollback: { strategy: 'none' },
  metadata: { priority: 'normal', depends_on: [], blocks: [] }
};

// Create a failing contract (impossible criterion)
const failContract = {
  id: 'tc-test-fail',
  type: 'code_fix',
  input: { description: 'Fix something that fails' },
  acceptance_criteria: [{
    type: 'file_contains',
    file: '/tmp/nonexistent-test-file-xyz.txt',
    pattern: 'impossible-pattern-abc123',
    description: 'File contains pattern'
  }],
  rollback: { strategy: 'none' },
  metadata: { priority: 'normal', depends_on: [], blocks: [] }
};

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

async function testAsync(name, fn) {
  try {
    await fn();
    console.log(`  ✅ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ❌ ${name}: ${e.message}`);
    failed++;
  }
}

async function run() {
  console.log('\n🧪 Auto-Retry Runner Tests\n');

  // Clean up
  const cleanup = () => {
    for (const f of ['test-pass.contract.json', 'test-pass.json', 'test-fail.contract.json', 'test-fail.json',
                      'test-esc.contract.json', 'test-esc.json']) {
      try { fs.unlinkSync(path.join(TASKS_DIR, f)); } catch {}
    }
    for (const f of fs.readdirSync('/tmp').filter(f => f.startsWith('retry-request-test') || f.startsWith('escalate-test'))) {
      try { fs.unlinkSync(path.join('/tmp', f)); } catch {}
    }
  };
  cleanup();

  // Test 1: Pass case
  await testAsync('handleAgentCompletion with pass → returns pass', async () => {
    fs.writeFileSync(path.join(TASKS_DIR, 'test-pass.contract.json'), JSON.stringify(passContract));
    fs.writeFileSync(path.join(TASKS_DIR, 'test-pass.json'), JSON.stringify({ agent_id: 'test', thread_id: 'pass' }));

    // Clear smart-retry history
    const smartRetry = require('../smart-retry');
    smartRetry.clearHistory('test-pass');

    const { handleAgentCompletion } = require('../auto-retry-runner');
    const result = await handleAgentCompletion('test', 'pass');
    assert.strictEqual(result.action, 'pass');
  });

  // Test 2: Failure creates retry request
  await testAsync('handleAgentCompletion with failure → creates retry request', async () => {
    fs.writeFileSync(path.join(TASKS_DIR, 'test-fail.contract.json'), JSON.stringify(failContract));
    fs.writeFileSync(path.join(TASKS_DIR, 'test-fail.json'), JSON.stringify({ agent_id: 'test', thread_id: 'fail' }));

    const smartRetry = require('../smart-retry');
    smartRetry.clearHistory('test-fail');

    // Need to re-require to get fresh state
    delete require.cache[require.resolve('../auto-retry-runner')];
    const { handleAgentCompletion } = require('../auto-retry-runner');
    const result = await handleAgentCompletion('test', 'fail');
    assert.strictEqual(result.action, 'retry');
    assert.ok(result.prompt, 'Should have retry prompt');
    assert.ok(fs.existsSync('/tmp/retry-request-test-fail.json'), 'Retry request file should exist');
  });

  // Test 3: Multiple failures → escalate
  await testAsync('3 failures → escalate', async () => {
    fs.writeFileSync(path.join(TASKS_DIR, 'test-esc.contract.json'), JSON.stringify(failContract));
    fs.writeFileSync(path.join(TASKS_DIR, 'test-esc.json'), JSON.stringify({ agent_id: 'test', thread_id: 'esc' }));

    const smartRetry = require('../smart-retry');
    smartRetry.clearHistory('test-esc');

    delete require.cache[require.resolve('../auto-retry-runner')];
    const { handleAgentCompletion } = require('../auto-retry-runner');

    let lastResult;
    for (let i = 0; i < 4; i++) {
      // Reset meta each time so it doesn't block
      fs.writeFileSync(path.join(TASKS_DIR, 'test-esc.json'), JSON.stringify({ agent_id: 'test', thread_id: 'esc' }));
      lastResult = await handleAgentCompletion('test', 'esc');
      if (lastResult.action === 'escalate') break;
    }
    assert.strictEqual(lastResult.action, 'escalate');
  });

  // Test 4: Watcher script format
  test('Watcher script exists and is executable', () => {
    const watcherPath = path.join(__dirname, '..', '..', 'auto-retry-watcher.sh');
    assert.ok(fs.existsSync(watcherPath), 'Watcher script should exist');
    const stats = fs.statSync(watcherPath);
    assert.ok(stats.mode & 0o100, 'Should be executable');
  });

  cleanup();

  console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

run();
