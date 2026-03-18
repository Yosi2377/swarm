/**
 * E2E test: full collaborative task flow.
 * Simulates: task assignment → discussion → code review → voting → resolution.
 * Run: node test/e2e-test.js
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
const DB_NAME = 'teamwork_collab_e2e';
const CONV_ID = 'e2e-task-001';

let client, cm, de, rs, rep;
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
  rs = new ReviewSystem({ client, dbName: DB_NAME });
  rep = new ReputationTracker({ client, dbName: DB_NAME });
  await cm.connect();
  await de.connect();
  await rs.connect();
  await rep.connect();

  const bridge = new TelegramBridge({ sendScript: '/bin/echo' });
  const injector = new PromptInjector();

  console.log('\n🚀 E2E Test: Full Collaborative Task Flow\n');

  // Step 1: Generate collaboration prompts
  console.log('Step 1: Prompt Generation');

  await test('generate collab prompts for all agents', () => {
    const agents = ['koder', 'shomer', 'front'];
    for (const a of agents) {
      const prompt = injector.generate('collab', {
        agentId: a,
        participants: agents.filter(x => x !== a),
        topic: 'Build auth module',
        conversationId: CONV_ID,
      });
      assert.ok(prompt.includes(a));
      assert.ok(prompt.includes('LISTEN before'));
    }
  });

  // Step 2: Task discussion
  console.log('\nStep 2: Task Discussion');

  await test('koder starts discussion', async () => {
    const res = await cm.sendMessage('koder', '__group__',
      'Task: Build auth module. I suggest JWT with refresh tokens.', {
      conversation_id: CONV_ID,
      addressed_to: ['shomer', 'front'],
    });
    assert.strictEqual(res.ok, true);
  });

  await test('shomer reviews security approach', async () => {
    await cm.listenForMessages('shomer', { conversation_id: CONV_ID });
    const res = await cm.sendMessage('shomer', '__group__',
      'JWT is fine but add token rotation and blacklist for compromised tokens.', {
      conversation_id: CONV_ID,
      addressed_to: ['koder'],
    });
    assert.strictEqual(res.ok, true);
  });

  await test('front asks about UI implications', async () => {
    await cm.listenForMessages('front', { conversation_id: CONV_ID });
    const res = await cm.sendMessage('front', '__group__',
      'How should the frontend handle token refresh? Silent refresh or redirect?', {
      conversation_id: CONV_ID,
      addressed_to: ['koder', 'shomer'],
    });
    assert.strictEqual(res.ok, true);
  });

  // Step 3: Decision on approach
  console.log('\nStep 3: Decision');

  let decisionId;
  await test('koder proposes decision on token refresh', async () => {
    await cm.listenForMessages('koder', { conversation_id: CONV_ID });
    const res = await de.proposeDecision('koder', 'Token refresh strategy',
      'Use silent refresh with rotation, blacklist on backend', { conversation_id: CONV_ID });
    assert.strictEqual(res.ok, true);
    decisionId = res.decision._id;
  });

  await test('all agents vote', async () => {
    const r1 = await de.vote('koder', decisionId, 'for', 'Best UX');
    const r2 = await de.vote('shomer', decisionId, 'for', 'Secure approach');
    const r3 = await de.vote('front', decisionId, 'for', 'Silent refresh is clean');
    assert.strictEqual(r1.ok, true);
    assert.strictEqual(r2.ok, true);
    assert.strictEqual(r3.ok, true);
  });

  await test('decision resolved', async () => {
    const res = await de.resolveDecision(decisionId, 'decided', ['koder', 'shomer', 'front']);
    assert.strictEqual(res.decision.status, 'decided');
  });

  // Step 4: Code implementation and review
  console.log('\nStep 4: Code Review');

  let reviewId;
  await test('koder implements and requests review', async () => {
    const code = `
    async function refreshToken(req, res) {
      const { refreshToken } = req.cookies;
      if (!refreshToken) return res.status(401).json({ error: 'No refresh token' });
      const payload = jwt.verify(refreshToken, SECRET);
      const newAccess = jwt.sign({ userId: payload.userId }, SECRET, { expiresIn: '15m' });
      const newRefresh = jwt.sign({ userId: payload.userId }, REFRESH_SECRET, { expiresIn: '7d' });
      await blacklistToken(refreshToken); // rotation
      res.cookie('refreshToken', newRefresh, { httpOnly: true, secure: true });
      return res.json({ accessToken: newAccess });
    }`;
    const res = await rs.requestReview('koder', code, 'JWT refresh with rotation', {
      reviewers: ['shomer', 'front'],
      conversation_id: CONV_ID,
    });
    assert.strictEqual(res.ok, true);
    reviewId = res.review._id;
  });

  await test('shomer approves with feedback', async () => {
    const res = await rs.submitReview('shomer', reviewId, 'approve',
      'Good rotation pattern. Consider adding rate limiting on refresh endpoint.');
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.escalated, false);
    await rep.recordEvent('shomer', 'review_submitted');
  });

  await test('front approves', async () => {
    const res = await rs.submitReview('front', reviewId, 'approve',
      'Cookie handling looks correct for silent refresh.');
    assert.strictEqual(res.ok, true);
    await rep.recordEvent('front', 'review_submitted');
  });

  // Step 5: Disagreement scenario
  console.log('\nStep 5: Disagreement & Escalation');

  let reviewId2;
  await test('koder submits controversial code for review', async () => {
    const res = await rs.requestReview('koder', 'eval(userInput)', 'Dynamic execution', {
      reviewers: ['shomer', 'front'],
      conversation_id: CONV_ID,
    });
    reviewId2 = res.review._id;
    assert.strictEqual(res.ok, true);
  });

  await test('shomer rejects (security risk)', async () => {
    const res = await rs.submitReview('shomer', reviewId2, 'reject',
      'CRITICAL: eval() with user input is a code injection vulnerability!');
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.escalated, false);
  });

  await test('front approves (functionality), triggers escalation', async () => {
    const res = await rs.submitReview('front', reviewId2, 'approve',
      'Works for our dynamic form use case.');
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.escalated, true);
  });

  await test('telegram bridge posts disagreement', () => {
    const review = { requested_by: 'koder', context: 'eval usage',
      reviews: [{ reviewer: 'shomer', verdict: 'reject' }, { reviewer: 'front', verdict: 'approve' }] };
    const res = bridge.postDisagreement(review, 10816);
    assert.strictEqual(res.ok, true);
  });

  // Step 6: Reputation tracking
  console.log('\nStep 6: Reputation');

  await test('record task completion for koder', async () => {
    await rep.recordEvent('koder', 'task_completed');
    await rep.recordEvent('koder', 'vote_cast');
    const r = await rep.getReputation('koder');
    assert.ok(r.score > 100);
  });

  await test('leaderboard reflects all agents', async () => {
    const board = await rep.getLeaderboard();
    assert.ok(board.length >= 2);
  });

  // Step 7: Smart context verification
  console.log('\nStep 7: Smart Context');

  await test('context buckets populated correctly', async () => {
    const ctx = await cm.getContext('koder', { conversation_id: CONV_ID });
    assert.ok(ctx.addressed.length > 0, 'Should have addressed messages');
    // Total across all buckets
    const total = ctx.addressed.length + ctx.channel.length + ctx.recent.length;
    assert.ok(total > 0, 'Should have context messages');
  });

  // Step 8: Budget enforcement across full flow
  console.log('\nStep 8: Budget Enforcement');

  await test('budget depletes after 2 unaddressed sends', async () => {
    await cm.listenForMessages('budget_test', { conversation_id: CONV_ID });
    await cm.sendMessage('budget_test', '__group__', 'Unaddressed 1', { conversation_id: CONV_ID });
    await cm.listenForMessages('budget_test');
    await cm.sendMessage('budget_test', '__group__', 'Unaddressed 2', { conversation_id: CONV_ID });
    await cm.listenForMessages('budget_test');
    const res = await cm.sendMessage('budget_test', '__group__', 'Unaddressed 3', { conversation_id: CONV_ID });
    assert.strictEqual(res.ok, false);
    assert.ok(res.error.includes('budget'));
  });

  // Step 9: Telegram bridge summary
  console.log('\nStep 9: Telegram Bridge');

  await test('post summary to telegram', () => {
    const res = bridge.postSummary({
      messageCount: 8,
      decisionCount: 1,
      reviewCount: 2,
      highlights: '- Auth module designed\n- JWT with rotation decided\n- eval() escalated',
    }, 10816);
    assert.strictEqual(res.ok, true);
  });

  await test('post decision to telegram', () => {
    const res = bridge.postDecision({
      topic: 'Token refresh strategy',
      status: 'decided',
      decision: 'Silent refresh with rotation',
      votes: { koder: { vote: 'for' }, shomer: { vote: 'for' }, front: { vote: 'for' } },
    }, 10816);
    assert.strictEqual(res.ok, true);
  });

  // Summary
  console.log(`\n${'='.repeat(50)}`);
  console.log(`E2E: ${passed} passed, ${failed} failed`);
  if (failures.length > 0) {
    console.log('\nFailures:');
    failures.forEach(f => console.log(`  ❌ ${f.name}: ${f.error}`));
  }

  await client.db(DB_NAME).dropDatabase();
  await client.close();
  process.exit(failed > 0 ? 1 : 0);
}

run().catch(err => {
  console.error('E2E test error:', err);
  process.exit(1);
});
