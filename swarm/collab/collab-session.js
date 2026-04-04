#!/usr/bin/env node
/**
 * Collab Session — Orchestrates a real collaborative discussion between agents.
 * 
 * Called by dispatch-task.sh with --collab flag.
 * Spawns multiple sub-agents that communicate through the collaboration system.
 * 
 * Usage: node collab-session.js --task "description" --agents "koder,shomer,front" --topic 12345 [--mode debate|review|collab]
 */

// No external API keys needed — uses Claude via OpenClaw

const fs = require('fs');
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
const JOB_ID_MATCH = String(TASK || '').match(/\[(job-\d+)\]/i);
const JOB_TAG = JOB_ID_MATCH ? `[${JOB_ID_MATCH[1]}] ` : '';
const LOCK_KEY = JOB_ID_MATCH ? JOB_ID_MATCH[1] : String(TOPIC_ID || 'collab');
const LOCK_DIR = '/tmp/swarm-collab-locks';
const LOCK_FILE = path.join(LOCK_DIR, `${LOCK_KEY}.lock`);

const ROLE_PERSPECTIVES = {
  koder: { emoji: '⚙️', focus: 'implementation, code architecture, performance', role: 'senior software engineer' },
  shomer: { emoji: '🔒', focus: 'security, vulnerabilities, hardening', role: 'cybersecurity expert' },
  front: { emoji: '🖥️', focus: 'UI/UX, responsive design, user experience', role: 'frontend developer and UX designer' },
  tzayar: { emoji: '🎨', focus: 'visual design, branding, aesthetics', role: 'visual designer' },
  researcher: { emoji: '🔍', focus: 'best practices, alternatives, research', role: 'technical researcher' },
  data: { emoji: '📊', focus: 'database design, data modeling, queries', role: 'database architect' },
  back: { emoji: '⚡', focus: 'API design, server architecture, scalability', role: 'backend engineer' },
  tester: { emoji: '🧪', focus: 'testing strategy, edge cases, quality', role: 'QA engineer' },
  debugger: { emoji: '🐛', focus: 'root cause analysis, logs, failures, debugging', role: 'debugging specialist' },
  worker: { emoji: '🤖', focus: 'general tasks, support', role: 'general engineer' },
};

function getRoleProfile(agent) {
  return ROLE_PERSPECTIVES[agent] || ROLE_PERSPECTIVES.worker;
}

function sendToTopic(agentId, msg) {
  try {
    const escaped = msg.replace(/'/g, "'\\''");
    execSync(`bash '${SEND_SH}' '${agentId}' '${TOPIC_ID}' '${escaped}'`, { timeout: 10000, stdio: 'pipe' });
  } catch {}
}

async function run() {
  fs.mkdirSync(LOCK_DIR, { recursive: true });
  if (fs.existsSync(LOCK_FILE)) {
    const pid = parseInt(fs.readFileSync(LOCK_FILE, 'utf8').trim(), 10);
    if (Number.isFinite(pid)) {
      try {
        process.kill(pid, 0);
        console.log(`collab session already running for ${LOCK_KEY} (pid ${pid})`);
        return;
      } catch (_) {}
    }
  }
  fs.writeFileSync(LOCK_FILE, String(process.pid));

  const cm = new ConversationManager();
  const de = new DecisionEngine();
  const rs = new ReviewSystem();
  const rep = new ReputationTracker();
  const isNumericTopic = /^\d+$/.test(String(TOPIC_ID));
  const bridge = isNumericTopic ? new TelegramBridge({ defaultTopic: parseInt(TOPIC_ID, 10) }) : null;
  const injector = new PromptInjector();
  const interMessageDelayMs = isNumericTopic ? 5000 : 1500;

  // Visible kickoff first so IRC users immediately see that consultation/voting started.
  sendToTopic(AGENTS[0], `🐝 סשן שיתוף פעולה (${MODE}) התחיל\nמשימה: ${TASK}\nמשתתפים: ${AGENTS.join(', ')}`);
  if (!isNumericTopic) {
    for (const agent of AGENTS.slice(1)) {
      sendToTopic(agent, `👀 ${agent}: נכנס לדיון על ${TASK} ומכין עמדה.`);
    }
  }

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
        await sleep(interMessageDelayMs);
      }
    }
  }

  // Decision phase: propose and collect explicit votes.
  sendToTopic(AGENTS[0], '🗳️ שלב הצבעה — כל סוכן מצביע בעד / נגד / נמנע עם נימוק קצר.');
  
  const allMsgsResult = await cm.listenForMessages(AGENTS[0], { conversation_id: convId });
  const discussionMessages = allMsgsResult.messages || [];
  
  const decResult = await de.proposeDecision(
    AGENTS[0],
    TASK,
    `Consensus from ${AGENTS.length}-agent ${MODE} session`,
    { conversation_id: convId },
  );

  const voteDetails = [];
  for (const agent of AGENTS) {
    const voteInfo = await generateAgentVote(agent, TASK, discussionMessages, MODE);
    voteDetails.push({ agent, ...voteInfo });
    await de.vote(agent, decResult.decision._id, voteInfo.vote, voteInfo.reason);
    await rep.recordEvent(agent, 'vote_cast');
    sendToTopic(agent, voteInfo.message);
    await sleep(interMessageDelayMs);
  }

  let tally = await de.getVoteTally(decResult.decision._id);
  const tieBreakers = [];
  if (tally && tally.for === tally.against && tally.for > 0) {
    sendToTopic(AGENTS[0], `⚖️ תיקו ${tally.for}-${tally.against}. מזמין סוכן מכריע נוסף.`);
    for (const tieBreaker of getTieBreakerCandidates(AGENTS)) {
      const voteInfo = await generateAgentVote(tieBreaker, TASK, discussionMessages, MODE, { tieBreaker: true, tally });
      tieBreakers.push(tieBreaker);
      voteDetails.push({ agent: tieBreaker, ...voteInfo, tieBreaker: true });
      await de.vote(tieBreaker, decResult.decision._id, voteInfo.vote, `[tie-break] ${voteInfo.reason}`);
      await rep.recordEvent(tieBreaker, 'vote_cast');
      sendToTopic(tieBreaker, voteInfo.message);
      await sleep(interMessageDelayMs);
      tally = await de.getVoteTally(decResult.decision._id);
      if (tally && tally.for !== tally.against) break;
    }
  }

  tally = await de.getVoteTally(decResult.decision._id);
  const decisionStatus = tally && tally.for >= tally.against ? 'decided' : 'overruled';
  const decidedBy = Object.entries((tally && tally.voters) || {})
    .filter(([, vote]) => vote === 'for')
    .map(([agent]) => agent);

  await de.resolveDecision(decResult.decision._id, decisionStatus, decidedBy);
  sendToTopic(
    AGENTS[0],
    `📊 תוצאת ההצבעה — בעד: ${tally?.for || 0}, נגד: ${tally?.against || 0}, נמנע: ${tally?.abstain || 0}${tieBreakers.length ? `\nקול מכריע: ${tieBreakers.join(', ')}` : ''}`,
  );

  // Post summary
  const summary = {
    messageCount: (await cm.listenForMessages(AGENTS[0], { conversation_id: convId })).messages.length,
    decisionCount: 1,
    reviewCount: 0,
    highlights: `${AGENTS.length + tieBreakers.length} agents collaborated on: ${TASK}` + (tieBreakers.length ? `\nTie-breaker: ${tieBreakers.join(', ')}` : ''),
  };
  
  if (bridge) {
    bridge.postSummary(summary, parseInt(TOPIC_ID, 10));
  } else {
    sendToTopic(AGENTS[0], `📊 Collaboration Summary\nMessages: ${summary.messageCount || 0}\nDecisions: ${summary.decisionCount || 0}\nReviews: ${summary.reviewCount || 0}${summary.highlights ? `\nHighlights:\n${summary.highlights}` : ''}`);
  }

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
 * Generate a REAL AI agent response using openclaw CLI.
 * Each agent gets its own AI call with role-specific system prompt.
 */
async function generateAgentResponse(agent, prompt, round, task, context) {
  const role = getRoleProfile(agent);
  
  // Build conversation history for context
  const historyLines = context.map(m => `${m.from}: ${m.content}`).join('\n');
  
  const systemPrompt = `You are ${agent}, a ${role.role} in a team discussion. Your expertise: ${role.focus}.
You are discussing: "${task}"
Round ${round + 1} of 4. Respond in Hebrew. Be specific, constructive, and concise (2-4 sentences max).
${round === 0 ? 'Share your initial professional opinion on this task.' : 'Respond to what others said — agree, disagree, or build on their ideas. Reference specific points.'}
${round === 3 ? 'This is the final round. State your concrete recommendation.' : ''}
Do NOT use generic filler. Give real technical insight from your perspective.
Start your message with: ${role.emoji} ${agent}:`;

  const userMsg = round === 0 
    ? `המשימה: ${task}\nמה דעתך המקצועית?`
    : `${historyLines}\n\nמה התגובה שלך?`;

  try {
    // Use openclaw CLI to spawn a quick agent response via Claude (no external APIs needed)
    const fs = require('fs');
    const fullPrompt = systemPrompt + '\n\n' + userMsg + '\n\nענה בקצרה (עד 200 מילים). תן תובנה מקצועית אמיתית.';
    const tmpFile = `/tmp/collab-prompt-${agent}-${Date.now()}.txt`;
    fs.writeFileSync(tmpFile, fullPrompt);
    
    const respondScript = path.resolve(__dirname, 'agent-respond.sh');
    const response = execSync(`bash "${respondScript}" "${tmpFile}"`, { 
      timeout: 190000, 
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env }
    }).toString().trim();
    
    // Cleanup temp file
    try { fs.unlinkSync(tmpFile); } catch(e) {}
    
    if (response && response.length > 5) {
      // Ensure it starts with the agent emoji
      if (!response.startsWith(role.emoji)) {
        return `${role.emoji} ${agent}: ${response}`;
      }
      return response;
    }
  } catch (err) {
    // Fallback to template if API fails
    console.error(`Claude call failed for ${agent}: ${err.message}`);
  }
  
  // Fallback: template response (should rarely happen)
  if (round === 0) {
    return `${role.emoji} ${agent}: מנקודת מבט של ${role.focus} — יש לי הערות על ${task}.`;
  }
  const lastMsg = context.length > 0 ? context[context.length - 1] : null;
  if (lastMsg) {
    return `${role.emoji} ${agent}: בתגובה ל-${lastMsg.from} — מבחינת ${role.focus}, צריך לשקול גם את ההיבטים האלה.`;
  }
  return `${role.emoji} ${agent}: ממשיך לנתח מבחינת ${role.focus}.`;
}

async function generateAgentVote(agent, task, context, mode, opts = {}) {
  const role = getRoleProfile(agent);
  const historyLines = (context || []).slice(-8).map(m => `${m.from}: ${m.content}`).join('\n');
  const tieBreakerNote = opts.tieBreaker ? `\nזהו קול מכריע בגלל תיקו קודם (${opts.tally?.for || 0}-${opts.tally?.against || 0}). אתה חייב להכריע בעד או נגד, לא נמנע.` : '';
  const prompt = `You are ${agent}, a ${role.role}.\nTask: ${task}\nMode: ${mode}\nRecent discussion:\n${historyLines || '(no recent messages)'}${tieBreakerNote}\n\nReturn EXACTLY in this format:\nVOTE: for|against|abstain\nREASON: one concise sentence in Hebrew\nMESSAGE: ${role.emoji} ${agent}: <brief Hebrew vote explanation>`;

  try {
    const fs = require('fs');
    const tmpFile = `/tmp/collab-vote-${agent}-${Date.now()}.txt`;
    fs.writeFileSync(tmpFile, prompt);
    const respondScript = path.resolve(__dirname, 'agent-respond.sh');
    const response = execSync(`bash "${respondScript}" "${tmpFile}"`, {
      timeout: 190000,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    }).toString().trim();
    try { fs.unlinkSync(tmpFile); } catch (e) {}

    const voteMatch = response.match(/VOTE:\s*(for|against|abstain)/i);
    const reasonMatch = response.match(/REASON:\s*(.+)/i);
    const messageMatch = response.match(/MESSAGE:\s*([\s\S]+)/i);
    const vote = voteMatch ? voteMatch[1].toLowerCase() : (opts.tieBreaker ? 'for' : 'abstain');
    const reason = reasonMatch ? reasonMatch[1].trim() : 'הצבעה ללא נימוק מפורש';
    let message = messageMatch ? messageMatch[1].trim() : `${role.emoji} ${agent}: ${vote === 'for' ? 'בעד' : vote === 'against' ? 'נגד' : 'נמנע'} — ${reason}`;
    if (!message.startsWith(role.emoji)) {
      message = `${role.emoji} ${agent}: ${message}`;
    }
    return { vote, reason, message };
  } catch (err) {
    const fallbackVote = opts.tieBreaker ? 'for' : 'abstain';
    return {
      vote: fallbackVote,
      reason: opts.tieBreaker ? 'קול מכריע ברירת מחדל עקב timeout' : 'timeout במהלך ההצבעה',
      message: `${role.emoji} ${agent}: ${fallbackVote === 'for' ? 'בעד' : 'נמנע'} — ${opts.tieBreaker ? 'מכריע כדי לשבור תיקו.' : 'לא הספקתי לנתח עד הסוף.'}`,
    };
  }
}

function getTieBreakerCandidates(participants) {
  const preferred = ['researcher', 'shomer', 'worker', 'tester', 'front', 'back', 'debugger', 'data', 'optimizer', 'integrator'];
  return preferred.filter((agent) => !participants.includes(agent));
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

run().catch(err => {
  console.error('Collab session failed:', err);
  process.exit(1);
});
