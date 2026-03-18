/**
 * Unit tests for all Agent Collaboration System modules.
 * Run: node test/unit-tests.js
 */

const { MongoClient } = require('mongodb');
const assert = require('assert');

const ConversationManager = require('../conversation-manager');
const DecisionEngine = require('../decision-engine');
const ReviewSystem = require('../review-system');
const ReputationTracker = require('../reputation');
const TelegramBridge = require('../telegram-bridge');
const PromptInjector = require('../prompt-injector');

const MONGO_URI = 'mongodb://localhost:27017';
const DB_NAME = 'teamwork_collab_test';

let client;
let passed = 0;
let failed = 0;
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

async function cleanup() {
  const db = client.db(DB_NAME);
  await db.dropDatabase();
}

async function runTests() {
  client = new MongoClient(MONGO_URI);
  await client.connect();
  await cleanup();

  console.log('\n📋 ConversationManager Tests');
  {
    const cm = new ConversationManager({ client, dbName: DB_NAME });
    await cm.connect();

    await test('sendMessage — basic send works', async () => {
      const res = await cm.sendMessage('koder', 'shomer', 'Hello!', { conversation_id: 'test1' });
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.message.from, 'koder');
      assert.strictEqual(res.message.to, 'shomer');
    });

    await test('sendMessage — send-after-listen enforcement', async () => {
      // Already sent once, should block second send without listen
      const s = cm._state('koder');
      s.sendLimit = 1;
      s.sendsSinceLastListen = 1;
      const res = await cm.sendMessage('koder', 'shomer', 'Second msg');
      assert.strictEqual(res.ok, false);
      assert.ok(res.error.includes('Must listen'));
    });

    await test('listenForMessages — resets send counter', async () => {
      const res = await cm.listenForMessages('koder', { conversation_id: 'test1' });
      const s = cm._state('koder');
      assert.strictEqual(s.sendsSinceLastListen, 0);
      assert.ok(Array.isArray(res.messages));
    });

    await test('sendMessage — budget enforcement for unaddressed', async () => {
      const s = cm._state('budget_agent');
      s.unaddressedSends = 2;
      s.budgetResetTime = Date.now();
      const res = await cm.sendMessage('budget_agent', '__group__', 'Spam');
      assert.strictEqual(res.ok, false);
      assert.ok(res.error.includes('budget depleted'));
    });

    await test('checkBudget — resets after window', async () => {
      const s = cm._state('budget_agent2');
      s.unaddressedSends = 2;
      s.budgetResetTime = Date.now() - 70000; // expired
      const b = cm.checkBudget('budget_agent2');
      assert.strictEqual(b.allowed, true);
      assert.strictEqual(b.remaining, 2);
    });

    await test('getAdaptiveCooldown — fast lane for addressed', () => {
      assert.strictEqual(cm.getAdaptiveCooldown(5, true), 500);
    });

    await test('getAdaptiveCooldown — slow lane scales with members', () => {
      assert.strictEqual(cm.getAdaptiveCooldown(3, false), 3000);
      assert.strictEqual(cm.getAdaptiveCooldown(1, false), 2000); // min 2000
    });

    await test('getContext — returns 3 buckets', async () => {
      // Send addressed message
      await cm.listenForMessages('koder');
      await cm.sendMessage('shomer', '__group__', 'Hey koder', {
        conversation_id: 'ctx1',
        addressed_to: ['koder'],
      });
      await cm.listenForMessages('shomer');
      await cm.sendMessage('shomer', '__group__', 'General msg', {
        conversation_id: 'ctx1',
        channel: 'general',
      });

      const ctx = await cm.getContext('koder', { conversation_id: 'ctx1' });
      assert.ok(Array.isArray(ctx.addressed));
      assert.ok(Array.isArray(ctx.channel));
      assert.ok(Array.isArray(ctx.recent));
    });

    await test('listenForMessages — should_respond true when addressed', async () => {
      await cm.listenForMessages('worker');
      await cm.sendMessage('koder', '__group__', 'Hey worker', {
        conversation_id: 'resp1',
        addressed_to: ['worker'],
      });
      const res = await cm.listenForMessages('worker', { conversation_id: 'resp1' });
      assert.strictEqual(res.should_respond, true);
    });

    await test('listenForMessages — priority sort works', async () => {
      await cm.listenForMessages('sorter');
      await cm.sendMessage('a', 'sorter', 'Direct', { conversation_id: 'sort1' });
      await cm.listenForMessages('a');
      await cm.sendMessage('b', 'sorter', 'Threaded', {
        conversation_id: 'sort1',
        reply_to: 'some-id',
      });
      const res = await cm.listenForMessages('sorter', { conversation_id: 'sort1' });
      assert.ok(res.messages.length >= 2);
    });
  }

  console.log('\n📋 DecisionEngine Tests');
  {
    const de = new DecisionEngine({ client, dbName: DB_NAME });
    await de.connect();

    let decisionId;

    await test('proposeDecision — creates proposal', async () => {
      const res = await de.proposeDecision('koder', 'Use TypeScript', 'Migrate to TS', { conversation_id: 'dec1' });
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.decision.status, 'proposed');
      assert.strictEqual(res.decision.proposed_by, 'koder');
      decisionId = res.decision._id;
    });

    await test('vote — records vote', async () => {
      const res = await de.vote('shomer', decisionId, 'for', 'Type safety is good');
      assert.strictEqual(res.ok, true);
      assert.ok(res.decision.votes.shomer);
      assert.strictEqual(res.decision.status, 'voting');
    });

    await test('vote — rejects invalid vote', async () => {
      const res = await de.vote('worker', decisionId, 'maybe');
      assert.strictEqual(res.ok, false);
      assert.ok(res.error.includes('Invalid vote'));
    });

    await test('getVoteTally — counts correctly', async () => {
      await de.vote('worker', decisionId, 'against', 'Too much work');
      const tally = await de.getVoteTally(decisionId);
      assert.strictEqual(tally.for, 1);
      assert.strictEqual(tally.against, 1);
      assert.strictEqual(tally.total, 2);
    });

    await test('resolveDecision — status transition', async () => {
      const res = await de.resolveDecision(decisionId, 'decided', ['koder', 'shomer']);
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.decision.status, 'decided');
    });

    await test('resolveDecision — rejects invalid transition', async () => {
      const res = await de.resolveDecision(decisionId, 'proposed');
      assert.strictEqual(res.ok, false);
    });

    await test('vote — cannot vote on decided', async () => {
      const res = await de.vote('data', decisionId, 'for');
      assert.strictEqual(res.ok, false);
    });

    await test('proposeDecision — overlap detection', async () => {
      const res = await de.proposeDecision('worker', 'Use TypeScript migration', 'Redo TS');
      assert.ok(res.overlap_warning);
    });

    await test('getDecisions — returns list', async () => {
      const decs = await de.getDecisions('dec1');
      assert.ok(decs.length >= 1);
    });
  }

  console.log('\n📋 ReviewSystem Tests');
  {
    const rs = new ReviewSystem({ client, dbName: DB_NAME });
    await rs.connect();

    let reviewId;

    await test('requestReview — creates review', async () => {
      const res = await rs.requestReview('koder', 'function add(a,b) { return a+b; }', 'Simple math', {
        reviewers: ['shomer', 'worker'],
      });
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.review.status, 'pending');
      reviewId = res.review._id;
    });

    await test('submitReview — approve', async () => {
      const res = await rs.submitReview('shomer', reviewId, 'approve', 'Looks good');
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.review.status, 'approved');
      assert.strictEqual(res.escalated, false);
    });

    await test('submitReview — reject causes escalation', async () => {
      const res = await rs.submitReview('worker', reviewId, 'reject', 'Missing edge cases');
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.escalated, true);
      assert.strictEqual(res.review.status, 'escalated');
    });

    await test('submitReview — rejects invalid verdict', async () => {
      const res = await rs.submitReview('data', reviewId, 'maybe', 'IDK');
      assert.strictEqual(res.ok, false);
    });

    await test('getPendingReviews — returns pending', async () => {
      await rs.requestReview('worker', 'code2', 'test2', { conversation_id: 'rev2' });
      const pending = await rs.getPendingReviews('shomer');
      assert.ok(pending.length >= 1);
    });

    await test('getReviews — returns by conversation', async () => {
      const reviews = await rs.getReviews('default');
      assert.ok(reviews.length >= 1);
    });
  }

  console.log('\n📋 ReputationTracker Tests');
  {
    const rep = new ReputationTracker({ client, dbName: DB_NAME });
    await rep.connect();

    await test('getReputation — initializes new agent', async () => {
      const r = await rep.getReputation('koder');
      assert.strictEqual(r.score, 100);
      assert.strictEqual(r.agent_id, 'koder');
    });

    await test('recordEvent — increases score', async () => {
      const res = await rep.recordEvent('koder', 'task_completed');
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.score, 110);
      assert.strictEqual(res.delta, 10);
    });

    await test('recordEvent — decreases score', async () => {
      const res = await rep.recordEvent('koder', 'bad_suggestion');
      assert.strictEqual(res.score, 107);
    });

    await test('recordEvent — custom delta', async () => {
      const res = await rep.recordEvent('shomer', 'custom_event', 25);
      assert.strictEqual(res.delta, 25);
      // shomer initialized at 100 + 25 = 125
      assert.ok(res.score >= 125, `Score should be >= 125, got ${res.score}`);
    });

    await test('applyDecay — decays inactive agents', async () => {
      // Make agent inactive for 5 days
      await rep.collection.updateOne(
        { agent_id: 'koder' },
        { $set: { last_active: new Date(Date.now() - 5 * 86400000) } }
      );
      const res = await rep.applyDecay();
      assert.ok(res.decayed.includes('koder'));
    });

    await test('getLeaderboard — sorted by score', async () => {
      const board = await rep.getLeaderboard();
      assert.ok(board.length >= 2);
      assert.ok(board[0].score >= board[1].score);
    });
  }

  console.log('\n📋 TelegramBridge Tests');
  {
    // Use a mock send script
    const bridge = new TelegramBridge({
      sendScript: '/bin/echo',
      defaultAgent: 'koder',
    });

    await test('post — sends message', () => {
      const res = bridge.post('koder', 10816, 'Test message');
      assert.strictEqual(res.ok, true);
    });

    await test('postDecision — formats correctly', () => {
      const res = bridge.postDecision({
        topic: 'Use TS',
        status: 'decided',
        decision: 'Migrate to TypeScript',
        votes: { koder: { vote: 'for' }, shomer: { vote: 'for' } },
      }, 10816);
      assert.strictEqual(res.ok, true);
    });

    await test('postDisagreement — formats correctly', () => {
      const res = bridge.postDisagreement({
        requested_by: 'koder',
        context: 'Math function',
        reviews: [
          { reviewer: 'shomer', verdict: 'approve' },
          { reviewer: 'worker', verdict: 'reject' },
        ],
      }, 10816);
      assert.strictEqual(res.ok, true);
    });

    await test('postResolution — formats correctly', () => {
      const res = bridge.postResolution('TypeScript migration', 'Approved, starting next sprint', 10816);
      assert.strictEqual(res.ok, true);
    });

    await test('postSummary — formats correctly', () => {
      const res = bridge.postSummary({
        messageCount: 15,
        decisionCount: 2,
        reviewCount: 3,
        highlights: '- Decided on TS\n- Code reviewed',
      }, 10816);
      assert.strictEqual(res.ok, true);
    });
  }

  console.log('\n📋 PromptInjector Tests');
  {
    const pi = new PromptInjector();

    await test('generate — collab template', () => {
      const prompt = pi.generate('collab', {
        agentId: 'koder',
        participants: ['shomer', 'worker'],
        topic: 'Architecture',
      });
      assert.ok(prompt.includes('koder'));
      assert.ok(prompt.includes('shomer, worker'));
      assert.ok(prompt.includes('Architecture'));
    });

    await test('generate — debate template', () => {
      const prompt = pi.generate('debate', { agentId: 'shomer', topic: 'Security' });
      assert.ok(prompt.includes('shomer'));
      assert.ok(prompt.includes('Debate'));
    });

    await test('generate — review template', () => {
      const prompt = pi.generate('review', { agentId: 'worker' });
      assert.ok(prompt.includes('worker'));
      assert.ok(prompt.includes('Review'));
    });

    await test('generateMinimal — returns rules', () => {
      const prompt = pi.generateMinimal('koder', 'debate');
      assert.ok(prompt.includes('koder'));
      assert.ok(prompt.includes('Vote honestly'));
    });

    await test('generateMinimal — review specific rules', () => {
      const prompt = pi.generateMinimal('shomer', 'review');
      assert.ok(prompt.includes('Review code carefully'));
    });
  }

  // Summary
  console.log(`\n${'='.repeat(50)}`);
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failures.length > 0) {
    console.log('\nFailures:');
    failures.forEach(f => console.log(`  ❌ ${f.name}: ${f.error}`));
  }

  await cleanup();
  await client.close();
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('Test runner error:', err);
  process.exit(1);
});
