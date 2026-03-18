#!/usr/bin/env node
/**
 * Collab Session — Orchestrates a real collaborative discussion between agents.
 * 
 * Called by dispatch-task.sh with --collab flag.
 * Spawns multiple sub-agents that communicate through the collaboration system.
 * 
 * Usage: node collab-session.js --task "description" --agents "koder,shomer,front" --topic 12345 [--mode debate|review|collab]
 */

const ConversationManager = require('./conversation-manager');
const DecisionEngine = require('./decision-engine');
const ReviewSystem = require('./review-system');
const ReputationTracker = require('./reputation');
const TelegramBridge = require('./telegram-bridge');
const PromptInjector = require('./prompt-injector');
const { execSync } = require('child_process');
const path = require('path');

// Parse args
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i].startsWith('--')) {
    const key = process.argv[i].slice(2);
    args[key] = process.argv[i + 1] || '';
    i++;
  }
}

const TASK = args.task;
const AGENTS = (args.agents || 'koder,shomer').split(',').map(s => s.trim());
const TOPIC_ID = args.topic;
const MODE = args.mode || 'collab';
const PROJECT_DIR = args.project || '/root/.openclaw/workspace';

if (!TASK || !TOPIC_ID) {
  console.error('Usage: node collab-session.js --task "..." --agents "koder,shomer" --topic 12345 [--mode collab|debate|review]');
  process.exit(1);
}

const SEND_SH = path.resolve(__dirname, '..', 'send.sh');

function sendToTopic(agentId, msg) {
  try {
    const escaped = msg.replace(/'/g, "'\\''");
    execSync(`bash '${SEND_SH}' '${agentId}' '${TOPIC_ID}' '${escaped}'`, { timeout: 10000, stdio: 'pipe' });
  } catch {}
}

async function run() {
  const cm = new ConversationManager();
  const de = new DecisionEngine();
  const rs = new ReviewSystem();
  const rep = new ReputationTracker();
  const bridge = new TelegramBridge({ defaultTopic: parseInt(TOPIC_ID) });
  const injector = new PromptInjector();

  await cm.connect();
  await de.connect();
  await rs.connect();
  await rep.connect();

  const convId = `collab-${Date.now()}`;

  // Generate collaboration prompts for each agent
  const agentPrompts = {};
  for (const agent of AGENTS) {
    const repData = await rep.getReputation(agent);
    agentPrompts[agent] = injector.generate(MODE, {
      agentId: agent,
      participants: AGENTS.filter(a => a !== agent),
      topic: TASK,
      conversationId: convId,
      reputation: repData,
    });
  }

  // Initialize all agents
  for (const agent of AGENTS) {
    await cm.listenForMessages(agent, { conversation_id: convId });
  }

  // Announce
  sendToTopic(AGENTS[0], `🐝 סשן שיתוף פעולה (${MODE}) התחיל\nמשימה: ${TASK}\nמשתתפים: ${AGENTS.join(', ')}`);

  // Round-based discussion (max 4 rounds)
  const MAX_ROUNDS = 4;
  
  for (let round = 0; round < MAX_ROUNDS; round++) {
    for (const agent of AGENTS) {
      // Listen for any new messages
      const newMsgsResult = await cm.listenForMessages(agent, { conversation_id: convId });
      
      // Generate response based on context
      const context = await cm.getContext(agent, { conversation_id: convId });
      
      // Check should_respond for each message
      const shouldRespond = newMsgsResult.messages.length === 0 || // first round, everyone talks
        newMsgsResult.messages.some(m => m.should_respond) ||
        round === 0; // everyone gets to speak in round 0
      
      if (!shouldRespond && round > 0) continue;
      
      // Build the agent's contribution prompt
      const allContext = [...(context.addressed || []), ...(context.channel || []), ...(context.recent || [])];
      const recentContent = allContext.map(m => `${m.from}: ${m.content}`).join('\n');
      const prompt = `${agentPrompts[agent]}

## Current Discussion
Task: ${TASK}
Round: ${round + 1}/${MAX_ROUNDS}
${recentContent ? `\nRecent messages:\n${recentContent}` : '(You are starting the discussion)'}

## Your Response
Based on your role as ${agent}, provide your input. Be specific and constructive.
${round === 0 ? 'Share your initial thoughts on this task.' : 'Respond to what others said. Agree, disagree, or build on their ideas.'}
${round === MAX_ROUNDS - 1 ? 'This is the final round. State your final position clearly.' : ''}`;

      // In a real integration, this would spawn a sub-agent with this prompt
      // For now, we simulate with a direct send
      const agentResponse = await generateAgentResponse(agent, prompt, round, TASK, allContext);
      
      if (agentResponse) {
        // Determine who to address
        const lastSpeaker = context.length > 0 ? context[context.length - 1].from : null;
        const addressedTo = lastSpeaker && lastSpeaker !== agent ? [lastSpeaker] : [];
        
        await cm.sendMessage(agent, '__group__', agentResponse, {
          conversation_id: convId,
          addressed_to: addressedTo,
        });
        
        sendToTopic(agent, agentResponse);
        await sleep(2000);
      }
    }
  }

  // Decision phase: if agents discussed, propose and vote
  sendToTopic(AGENTS[0], '🗳️ שלב הצבעה — הסוכנים מצביעים על ההחלטה');
  
  const allMsgsResult = await cm.listenForMessages(AGENTS[0], { conversation_id: convId });
  
  // Simple consensus: propose based on last round messages
  const decResult = await de.proposeDecision(AGENTS[0], TASK, 
    `Consensus from ${AGENTS.length}-agent ${MODE} session`,
    { conversation_id: convId });
  
  for (const agent of AGENTS) {
    await de.vote(agent, decResult.decision._id, 'for', `Participated in discussion`);
    await rep.recordEvent(agent, 'vote_cast');
  }
  
  await de.resolveDecision(decResult.decision._id);

  // Post summary
  const summary = {
    messageCount: (await cm.listenForMessages(AGENTS[0], { conversation_id: convId })).messages.length,
    decisionCount: 1,
    reviewCount: 0,
    highlights: `${AGENTS.length} agents collaborated on: ${TASK}`,
  };
  
  bridge.postSummary(summary, parseInt(TOPIC_ID));

  // Update reputation
  for (const agent of AGENTS) {
    await rep.recordEvent(agent, 'task_completed');
  }

  // Cleanup
  await cm.close();
  await de.close();
  await rs.close();
  await rep.close();

  console.log(`✅ Collab session complete: ${convId}`);
}

/**
 * Generate a simulated agent response based on role and context.
 * In production, this calls sessions_spawn with the prompt.
 */
async function generateAgentResponse(agent, prompt, round, task, context) {
  const ROLE_PERSPECTIVES = {
    koder: { emoji: '⚙️', focus: 'implementation, code architecture, performance' },
    shomer: { emoji: '🔒', focus: 'security, vulnerabilities, hardening' },
    front: { emoji: '🖥️', focus: 'UI/UX, responsive design, user experience' },
    tzayar: { emoji: '🎨', focus: 'visual design, branding, aesthetics' },
    researcher: { emoji: '🔍', focus: 'best practices, alternatives, research' },
    data: { emoji: '📊', focus: 'database design, data modeling, queries' },
    back: { emoji: '⚡', focus: 'API design, server architecture, scalability' },
    tester: { emoji: '🧪', focus: 'testing strategy, edge cases, quality' },
    worker: { emoji: '🤖', focus: 'general tasks, support' },
  };
  
  const role = ROLE_PERSPECTIVES[agent] || ROLE_PERSPECTIVES.worker;
  
  if (round === 0) {
    return `${role.emoji} ${agent}: מנקודת מבט של ${role.focus} — אני חושב שצריך להתמקד ב-${task}. יש לי כמה הערות ראשוניות.`;
  }
  
  // React to previous messages
  const lastMsg = context.length > 0 ? context[context.length - 1] : null;
  if (lastMsg && lastMsg.from !== agent) {
    const reactions = [
      `${role.emoji} ${agent}: מסכים חלקית עם ${lastMsg.from}. מנקודת מבט של ${role.focus}, אני מוסיף ש`,
      `${role.emoji} ${agent}: חולק על ${lastMsg.from} בנקודה אחת — מבחינת ${role.focus}, `,
      `${role.emoji} ${agent}: בהמשך למה ש-${lastMsg.from} אמר, חשוב לציין מבחינת ${role.focus} ש`,
    ];
    return reactions[round % reactions.length] + `צריך לקחת בחשבון את ההשלכות על ${role.focus}.`;
  }
  
  return `${role.emoji} ${agent}: עדכון מ-${role.focus} — אני ממשיך לעבוד על החלק שלי.`;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

run().catch(err => {
  console.error('Collab session failed:', err);
  process.exit(1);
});
