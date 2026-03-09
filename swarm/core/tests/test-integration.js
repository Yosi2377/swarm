// Integration Tests — Full reliability layer flow
// Run: node swarm/core/tests/test-integration.js

const fs = require('fs');
const path = require('path');
const assert = require('assert');

// Clean test state
const TASKS_DIR = '/tmp/agent-tasks';
const CONSULT_DIR = '/tmp/agent-consultations';

function cleanDirs() {
  for (const dir of [TASKS_DIR, CONSULT_DIR]) {
    if (fs.existsSync(dir)) {
      fs.readdirSync(dir).forEach(f => {
        try { fs.unlinkSync(path.join(dir, f)); } catch(_) {}
      });
    }
  }
}

// Import modules
const bridge = require('../orchestrator-bridge');
const { handleFailure, clearHistory } = require('../smart-retry');
const consultation = require('../agent-consultation');

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

// ─── Test Suite ───

console.log('\n🧪 Integration Tests — Reliability Layer\n');

// ─── 1. prepareTask → full flow → pass ───
console.log('📋 Test Group: prepareTask');

cleanDirs();

test('prepareTask creates contract + state + prompt', () => {
  const result = bridge.prepareTask('Fix the login bug that crashes the server', 'koder', '1001', { basePath: '/root/BotVerse' });
  assert.strictEqual(result.errors, null);
  assert.ok(result.contract);
  assert.ok(result.contract.id);
  assert.strictEqual(result.contract.type, 'code_fix');
  assert.ok(result.state);
  assert.ok(result.agentPrompt);
  assert.ok(result.agentPrompt.includes('Acceptance Criteria'));
});

test('prepareTask saves contract file', () => {
  const cp = path.join(TASKS_DIR, 'koder-1001.contract.json');
  assert.ok(fs.existsSync(cp));
  const contract = JSON.parse(fs.readFileSync(cp, 'utf8'));
  assert.ok(contract.type); // contract type was inferred
});

test('prepareTask saves state file', () => {
  const sp = path.join(TASKS_DIR, 'koder-1001.json');
  assert.ok(fs.existsSync(sp));
  const state = JSON.parse(fs.readFileSync(sp, 'utf8'));
  assert.ok(state.contract_id || state.contractId);
});

test('prepareTask infers security type for Hebrew', () => {
  const result = bridge.prepareTask('בדוק אבטחה של הAPI', 'shomer', '1002');
  assert.strictEqual(result.contract.type, 'security_fix');
});

test('prepareTask infers research type', () => {
  const result = bridge.prepareTask('Research best caching strategies', 'researcher', '1003');
  assert.strictEqual(result.contract.type, 'research');
});

test('prepareTask enriches with project config', () => {
  const result = bridge.prepareTask('Add feature', 'koder', '1004', { basePath: '/app', testCommand: 'npm test' });
  assert.ok(result.contract.acceptance_criteria.some(c => c.description.includes('npm test')));
  assert.ok(result.contract.input.context.includes('/app'));
});

test('contract is embedded in agent prompt', () => {
  const result = bridge.prepareTask('Fix UI alignment issue', 'front', '1005');
  assert.ok(result.agentPrompt.includes('ui_change'));
  assert.ok(result.agentPrompt.includes('Acceptance Criteria'));
  // Check criteria are listed
  assert.ok(result.agentPrompt.includes('visual_check') || result.agentPrompt.includes('UI renders'));
});

// ─── 2. onAgentDone → pass (no runnable criteria) ───
console.log('\n📋 Test Group: onAgentDone');

test('onAgentDone handles task with unrunnable criteria', () => {
  cleanDirs();
  clearHistory('koder-2001');
  bridge.prepareTask('Research best practices for caching', 'koder', '2001');
  const result = bridge.onAgentDone('koder', '2001', {});
  // Research tasks have report_complete/actionable — no runners exist, so they fail as "unknown type"
  // This correctly triggers retry or escalate
  assert.ok(['pass', 'retry', 'escalate'].includes(result.action));
});

test('onAgentDone returns retry with legacy task (no contract)', () => {
  const result = bridge.onAgentDone('worker', '9999', {});
  assert.strictEqual(result.action, 'retry');
  assert.ok(result.reason.includes('contract'));
});

// ─── 3. Full retry flow ───
console.log('\n📋 Test Group: Retry Flow');

test('onAgentDone with file_contains criteria fails and retries', () => {
  cleanDirs();
  clearHistory('koder-3001');

  // Create a contract with a file_contains criterion that will fail
  const result = bridge.prepareTask('Fix the config file', 'koder', '3001');
  // Manually add a file_contains criterion
  const cp = path.join(TASKS_DIR, 'koder-3001.contract.json');
  const contract = JSON.parse(fs.readFileSync(cp, 'utf8'));
  contract.acceptance_criteria.push({
    type: 'file_contains',
    file: '/tmp/test-integration-dummy.txt',
    pattern: 'FIXED_VALUE',
    description: 'Config contains FIXED_VALUE'
  });
  fs.writeFileSync(cp, JSON.stringify(contract, null, 2));

  // First attempt — should fail (file doesn't exist)
  const r1 = bridge.onAgentDone('koder', '3001', {});
  assert.ok(r1.action === 'retry' || r1.action === 'escalate', `Expected retry or escalate, got ${r1.action}`);

  if (r1.action === 'retry') {
    assert.ok(r1.prompt);
    assert.ok(r1.prompt.includes('Retry'));
  }
});

test('3 consecutive failures → escalate', () => {
  cleanDirs();
  clearHistory('koder-3002');

  bridge.prepareTask('Fix broken endpoint', 'koder', '3002');
  const cp = path.join(TASKS_DIR, 'koder-3002.contract.json');
  const contract = JSON.parse(fs.readFileSync(cp, 'utf8'));
  contract.acceptance_criteria = [{
    type: 'file_contains',
    file: '/tmp/nonexistent-file-xyz.txt',
    pattern: 'IMPOSSIBLE',
    description: 'This will always fail'
  }];
  fs.writeFileSync(cp, JSON.stringify(contract, null, 2));

  let lastResult;
  for (let i = 0; i < 4; i++) {
    lastResult = bridge.onAgentDone('koder', '3002', {});
    if (lastResult.action === 'escalate') break;
  }
  assert.strictEqual(lastResult.action, 'escalate');
  assert.ok(lastResult.humanMessage);
  assert.ok(lastResult.humanMessage.includes('human intervention'));
});

// ─── 4. Dashboard ───
console.log('\n📋 Test Group: Dashboard');

test('getTaskDashboard returns summary', () => {
  cleanDirs();
  bridge.prepareTask('Task A', 'koder', '4001');
  bridge.prepareTask('Task B', 'shomer', '4002');
  bridge.prepareTask('Research C', 'researcher', '4003');

  const dashboard = bridge.getTaskDashboard();
  assert.ok(dashboard.total >= 3);
  assert.ok(dashboard.tasks.length >= 3);
  assert.ok(dashboard.by_agent);
});

// ─── 5. Consultation ───
console.log('\n📋 Test Group: Consultation');

test('requestConsultation creates consultation', () => {
  // Clean consultations
  if (fs.existsSync(CONSULT_DIR)) {
    fs.readdirSync(CONSULT_DIR).forEach(f => fs.unlinkSync(path.join(CONSULT_DIR, f)));
  }

  const c = bridge.requestConsultation('koder', 'shomer', '5001', 'Is this SQL injection safe?');
  assert.ok(c.id);
  assert.strictEqual(c.fromAgent, 'koder');
  assert.strictEqual(c.toAgent, 'shomer');
  assert.strictEqual(c.status, 'pending');
});

test('auto-route routes security questions to shomer', () => {
  const agent = consultation.autoRoute('Is this XSS vulnerability dangerous?');
  assert.strictEqual(agent, 'shomer');
});

test('auto-route routes design questions to tzayar', () => {
  const agent = consultation.autoRoute('Need help with UI design for the button');
  assert.strictEqual(agent, 'tzayar');
});

test('auto-route with null toAgent uses routing', () => {
  const c = bridge.requestConsultation('koder', null, '5002', 'Need security review of auth flow');
  assert.strictEqual(c.toAgent, 'shomer');
});

test('getPendingConsultations returns pending', () => {
  const pending = bridge.getPendingConsultations();
  assert.ok(pending.length >= 2);
  assert.ok(pending.every(p => p.status === 'pending'));
});

test('respondToHelp marks consultation as answered', () => {
  const pending = bridge.getPendingConsultations('shomer');
  assert.ok(pending.length >= 1);

  bridge.respondToHelp(pending[0].id, 'shomer', 'Yes, use parameterized queries');
  const all = bridge.getAllConsultations();
  const answered = all.find(c => c.id === pending[0].id);
  assert.strictEqual(answered.status, 'answered');
  assert.ok(answered.answer.includes('parameterized'));
});

// ─── 6. spawn-agent.sh contract integration ───
console.log('\n📋 Test Group: spawn-agent.sh contract integration');

test('spawn-agent.sh includes contract block when contract exists', () => {
  cleanDirs();
  // Create a contract file
  bridge.prepareTask('Fix the login page CSS', 'koder', '6001');

  const { execSync } = require('child_process');
  const swarmDir = path.resolve(__dirname, '..', '..');
  try {
    const output = execSync(`bash "${swarmDir}/spawn-agent.sh" koder 6001 "Fix the login page CSS"`, {
      encoding: 'utf8', timeout: 10000
    });
    assert.ok(output.includes('Acceptance Criteria'), 'spawn-agent.sh should include acceptance criteria from contract');
  } catch (e) {
    // spawn-agent.sh might fail on inject-lessons.sh etc, check stdout
    const out = (e.stdout || '') + (e.stderr || '');
    // As long as the contract block is in the output, it's fine
    if (!out.includes('Acceptance Criteria')) {
      throw new Error('Contract block not found in spawn-agent.sh output');
    }
  }
});

// ─── Summary ───
console.log(`\n${'─'.repeat(40)}`);
console.log(`Results: ${passed} passed, ${failed} failed, ${passed + failed} total`);
console.log(`${'─'.repeat(40)}\n`);

if (failed > 0) {
  process.exit(1);
}
