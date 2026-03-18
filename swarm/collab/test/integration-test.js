/**
 * Integration test: simulate 3 agents debating an architecture decision.
 * Run: node test/integration-test.js
 */

const { MongoClient } = require('mongodb');
const assert = require('assert');

const ConversationManager = require('../conversation-manager');
const DecisionEngine = require('../decision-engine');
const ReputationTracker = require('../reputation');

const MONGO_URI = 'mongodb://localhost:27017';
const DB_NAME = 'teamwork_collab_inttest';
const CONV_ID = 'arch-debate-001';

let client, cm, de, rep;
let passed = 0, failed = 0;
const failures = [];

async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (err) {
    failed++;
    failures.push({ name, error: err.message });
    console.log(`  ❌ ${name}: ${err.message}`);
  }
}

async function run() {
  client = new MongoClient(MONGO_URI);
  await client.connect();
  await client.db(DB_NAME).dropDatabase();

  cm = new ConversationManager({ client, dbName: DB_NAME });
  de = new DecisionEngine({ client, dbName: DB_NAME });
  rep = new ReputationTracker({ client, dbName: DB_NAME });
  await cm.connect();
  await de.connect();
  await rep.connect();

  console.log('\n🏗️ Integration Test: 3 Agents Debating Architecture\n');

  // Phase 1: koder proposes a decision
  console.log('Phase 1: Proposal');
  let decisionId;

  await test('koder proposes "Use microservices architecture"', async () => {
    const res = await de.proposeDecision('koder', 'Use microservices architecture',
      'Split monolith into microservices for scalability', { conversation_id: CONV_ID });
    assert.strictEqual(res.ok, true);
    decisionId = res.decision._id;
    await rep.recordEvent('koder', 'decision_made');
  });

  await test('koder announces proposal in conversation', async () => {
    const res = await cm.sendMessage('koder', '__group__', 
      'I propose we use microservices architecture. Decision ID: ' + decisionId, {
      conversation_id: CONV_ID,
      addressed_to: ['shomer', 'back'],
      type: 'message',
    });
    assert.strictEqual(res.ok, true);
  });

  // Phase 2: agents listen and respond
  console.log('\nPhase 2: Discussion');

  await test('shomer listens and sees the proposal', async () => {
    const res = await cm.listenForMessages('shomer', { conversation_id: CONV_ID });
    assert.strictEqual(res.should_respond, true);
    assert.ok(res.messages.some(m => m.content.includes('microservices')));
  });

  await test('shomer responds with concerns', async () => {
    const res = await cm.sendMessage('shomer', '__group__',
      'Security concern: microservices increase attack surface. Each service needs its own auth.', {
      conversation_id: CONV_ID,
      addressed_to: ['koder'],
    });
    assert.strictEqual(res.ok, true);
    await rep.recordEvent('shomer', 'helpful_feedback');
  });

  await test('back listens and responds', async () => {
    await cm.listenForMessages('back', { conversation_id: CONV_ID });
    const res = await cm.sendMessage('back', '__group__',
      'I support microservices but suggest starting with 3 core services, not full split.', {
      conversation_id: CONV_ID,
      addressed_to: ['koder', 'shomer'],
    });
    assert.strictEqual(res.ok, true);
  });

  await test('koder listens and sees both responses', async () => {
    const res = await cm.listenForMessages('koder', { conversation_id: CONV_ID });
    assert.ok(res.messages.length >= 2);
  });

  await test('koder acknowledges and refines', async () => {
    const res = await cm.sendMessage('koder', '__group__',
      'Good points. Updated proposal: start with 3 microservices, each with dedicated auth.', {
      conversation_id: CONV_ID,
      addressed_to: ['shomer', 'back'],
    });
    assert.strictEqual(res.ok, true);
  });

  // Phase 3: Voting
  console.log('\nPhase 3: Voting');

  await test('koder votes for', async () => {
    const res = await de.vote('koder', decisionId, 'for', 'My proposal, refined with feedback');
    assert.strictEqual(res.ok, true);
    await rep.recordEvent('koder', 'vote_cast');
  });

  await test('shomer votes for (concerns addressed)', async () => {
    const res = await de.vote('shomer', decisionId, 'for', 'Auth per service addresses my concern');
    assert.strictEqual(res.ok, true);
    await rep.recordEvent('shomer', 'vote_cast');
  });

  await test('back votes for', async () => {
    const res = await de.vote('back', decisionId, 'for', 'Gradual approach is sensible');
    assert.strictEqual(res.ok, true);
    await rep.recordEvent('back', 'vote_cast');
  });

  await test('vote tally shows 3 for', async () => {
    const tally = await de.getVoteTally(decisionId);
    assert.strictEqual(tally.for, 3);
    assert.strictEqual(tally.against, 0);
    assert.strictEqual(tally.total, 3);
  });

  // Phase 4: Resolution
  console.log('\nPhase 4: Resolution');

  await test('decision is resolved as decided', async () => {
    const res = await de.resolveDecision(decisionId, 'decided', ['koder', 'shomer', 'back']);
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.decision.status, 'decided');
  });

  await test('koder announces resolution', async () => {
    await cm.listenForMessages('koder', { conversation_id: CONV_ID });
    const res = await cm.sendMessage('koder', '__group__',
      '✅ Decision: Use microservices (3 core services, dedicated auth). Unanimous.', {
      conversation_id: CONV_ID,
      type: 'decision',
    });
    assert.strictEqual(res.ok, true);
  });

  // Phase 5: Overlap detection
  console.log('\nPhase 5: Overlap Detection');

  await test('new proposal on same topic triggers overlap warning', async () => {
    const res = await de.proposeDecision('worker', 'Use microservices for scaling',
      'We should use microservices');
    assert.ok(res.overlap_warning);
    assert.ok(res.overlap_warning.includes('already'));
  });

  // Phase 6: Context verification
  console.log('\nPhase 6: Smart Context');

  await test('getContext returns addressed messages in bucket A', async () => {
    const ctx = await cm.getContext('koder', { conversation_id: CONV_ID });
    assert.ok(ctx.addressed.length > 0);
  });

  // Phase 7: Reputation check
  console.log('\nPhase 7: Reputation');

  await test('reputation reflects contributions', async () => {
    const kRep = await rep.getReputation('koder');
    assert.ok(kRep.score > 100, `koder score ${kRep.score} should be > 100`);
    const board = await rep.getLeaderboard();
    assert.ok(board.length >= 3);
  });

  // Summary
  console.log(`\n${'='.repeat(50)}`);
  console.log(`Integration: ${passed} passed, ${failed} failed`);
  if (failures.length > 0) {
    console.log('\nFailures:');
    failures.forEach(f => console.log(`  ❌ ${f.name}: ${f.error}`));
  }

  await client.db(DB_NAME).dropDatabase();
  await client.close();
  process.exit(failed > 0 ? 1 : 0);
}

run().catch(err => {
  console.error('Integration test error:', err);
  process.exit(1);
});
