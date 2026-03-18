#!/usr/bin/env node
/**
 * Demo: 3 agents (koder, shomer, front) collaborate on a task.
 * They discuss, disagree, vote, and reach a decision — all posted to Telegram.
 * 
 * Usage: node demo-collab.js <topic_id>
 */

const ConversationManager = require('./conversation-manager');
const DecisionEngine = require('./decision-engine');
const ReviewSystem = require('./review-system');
const ReputationTracker = require('./reputation');
const TelegramBridge = require('./telegram-bridge');
const PromptInjector = require('./prompt-injector');

const TOPIC_ID = process.argv[2] || null;
if (!TOPIC_ID) {
  console.error('Usage: node demo-collab.js <telegram_topic_id>');
  process.exit(1);
}

async function runDemo() {
  const cm = new ConversationManager();
  const de = new DecisionEngine();
  const rs = new ReviewSystem();
  const rep = new ReputationTracker();
  const bridge = new TelegramBridge();
  const injector = new PromptInjector();

  await cm.connect();
  await de.connect();
  await rs.connect();
  await rep.connect();

  const convId = 'demo-' + Date.now();
  const agents = ['koder', 'shomer', 'front'];

  // Initialize: all agents listen first (resets send-after-listen)
  await cm.listenForMessages('koder', { conversation_id: convId });
  await cm.listenForMessages('shomer', { conversation_id: convId });
  await cm.listenForMessages('front', { conversation_id: convId });

  // Phase 1: Koder proposes architecture
  bridge.post('koder', TOPIC_ID, '💬 קודר: אני מציע לבנות את ה-API עם Express + MongoDB. מהיר ופשוט.');

  await cm.sendMessage('koder', '__group__', 
    'I propose building the API with Express + MongoDB. Fast and simple.', 
    { conversation_id: convId, addressed_to: [] });

  await sleep(2000);

  // Phase 2: Shomer disagrees
  const msgs1 = await cm.listenForMessages('shomer', { conversation_id: convId });

  bridge.post('shomer', TOPIC_ID, '🔒 שומר: רגע, Express בלי rate limiting ו-helmet? יש בעיות אבטחה. אני מציע Fastify עם built-in validation.');

  await cm.sendMessage('shomer', '__group__',
    'Hold on. Express without rate limiting and helmet has security issues. I suggest Fastify with built-in schema validation.',
    { conversation_id: convId, addressed_to: ['koder'] });

  await sleep(2000);

  // Phase 3: Front adds perspective
  const msgs2 = await cm.listenForMessages('front', { conversation_id: convId });

  bridge.post('front', TOPIC_ID, '🖥️ פרונט: מבחינתי שני הפתרונות עובדים. השאלה היא מה ה-response format — אני צריך JSON עקבי עם error codes.');

  await cm.sendMessage('front', '__group__',
    'Both work for me. The real question is the response format — I need consistent JSON with proper error codes.',
    { conversation_id: convId, addressed_to: ['koder', 'shomer'] });

  await sleep(2000);

  // Phase 4: Koder listens and adjusts
  const msgs3 = await cm.listenForMessages('koder', { conversation_id: convId });

  bridge.post('koder', TOPIC_ID, '⚙️ קודר: אוקיי שומר, נקודה טובה. אני מוכן ללכת על Fastify. בואו נצביע.');

  await cm.sendMessage('koder', '__group__',
    'OK shomer, fair point. I\'m willing to go with Fastify. Let\'s vote on it.',
    { conversation_id: convId, addressed_to: ['shomer'] });

  await sleep(1500);

  // Phase 5: Decision proposal + voting
  const decResult = await de.proposeDecision('koder', 'API Framework', 
    'Use Fastify with schema validation instead of Express',
    { conversation_id: convId });
  const decision = decResult.decision;

  bridge.post('koder', TOPIC_ID, '🗳️ הצבעה: Fastify עם schema validation במקום Express');

  await sleep(1000);

  await de.vote('koder', decision._id || decision.insertedId, 'for', 'Better security out of the box');
  await de.vote('shomer', decision._id || decision.insertedId, 'for', 'Built-in validation and secure defaults');
  await de.vote('front', decision._id || decision.insertedId, 'for', 'Consistent with type-safe response format');

  const resolved = await de.resolveDecision(decision._id || decision.insertedId);

  bridge.postDecision({
    topic: 'API Framework',
    status: 'decided',
    decision: 'Use Fastify with schema validation',
    votes: { koder: 'for', shomer: 'for', front: 'for' }
  }, TOPIC_ID);

  await sleep(2000);

  // Phase 6: Code review
  bridge.post('koder', TOPIC_ID, '⚙️ קודר: כתבתי את ה-API. שומר, תבדוק בבקשה.');

  const review = await rs.requestReview('koder', convId,
    'const app = require("fastify")({ logger: true }); app.register(require("fastify-helmet"));',
    'Initial API setup with Fastify + Helmet');

  await sleep(1500);

  // Shomer reviews with a concern
  const reviewId = review._id || review.insertedId;
  await rs.submitReview('shomer', reviewId, 'changes_requested',
    'Good start but missing rate-limiter. Add fastify-rate-limit.');

  bridge.post('shomer', TOPIC_ID, '🔒 שומר: ביקורת — חסר rate limiter. תוסיף fastify-rate-limit.');

  await sleep(1500);

  // Koder fixes and resubmits
  bridge.post('koder', TOPIC_ID, '⚙️ קודר: תיקנתי, הוספתי rate-limit. שומר?');

  await rs.submitReview('shomer', reviewId, 'approved',
    'Rate limiter added. LGTM. ✅');

  bridge.post('shomer', TOPIC_ID, '🔒 שומר: מאושר ✅');

  // Phase 7: Reputation update
  await rep.recordEvent('koder', 'review_addressed', 5);
  await rep.recordEvent('shomer', 'good_review', 5);
  await rep.recordEvent('front', 'helpful_feedback', 3);

  await sleep(1500);

  // Phase 8: Summary
  const kRep = await rep.getReputation('koder');
  const sRep = await rep.getReputation('shomer');
  const fRep = await rep.getReputation('front');

  bridge.postSummary({
    messageCount: 6,
    decisionCount: 1,
    reviewCount: 1,
    highlights: `• Framework: Fastify (unanimous)\n• Review: rate-limit fix → approved\n• Rep: koder=${kRep.score}, shomer=${sRep.score}, front=${fRep.score}`
  }, TOPIC_ID);

  bridge.postResolution('API Framework Selection',
    'Fastify with schema validation + helmet + rate-limit. Unanimously approved after code review.',
    TOPIC_ID);

  // Cleanup
  await cm.close();
  await de.close();
  await rs.close();
  await rep.close();

  console.log('✅ Demo complete. Check Telegram topic', TOPIC_ID);
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

runDemo().catch(err => {
  console.error('Demo failed:', err);
  process.exit(1);
});
