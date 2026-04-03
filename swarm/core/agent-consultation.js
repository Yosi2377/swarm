// Agent Consultation — inter-agent communication via Agent Chat (topic 479)

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SWARM_DIR = path.resolve(__dirname, '..');
const SEND_SH = path.join(SWARM_DIR, 'send.sh');
const CONSULT_DIR = '/tmp/agent-consultations';
function getAgentChatTopic() {
  try {
    const runtime = JSON.parse(fs.readFileSync(path.join(SWARM_DIR, 'runtime.json'), 'utf8'));
    if ((runtime.transport || '').toLowerCase() === 'irc') return '#agent-chat';
  } catch (_) {}
  return '479';
}

const AGENT_EMOJIS = {
  or: '🐝', shomer: '🔒', koder: '⚙️', tzayar: '🎨',
  worker: '🤖', researcher: '🔍', bodek: '🧪', data: '📊',
  debugger: '🐛', docker: '🐳', front: '🖥️', back: '⚡',
  tester: '🧪', refactor: '♻️', monitor: '📡', optimizer: '🚀',
  integrator: '🔗'
};

// Auto-routing: keyword → agent
const ROUTING_RULES = [
  { keywords: ['security', 'אבטחה', 'xss', 'csrf', 'injection', 'ssl', 'vulnerability'], agent: 'shomer' },
  { keywords: ['code', 'קוד', 'bug', 'באג', 'api', 'node', 'deploy'], agent: 'koder' },
  { keywords: ['design', 'עיצוב', 'ui', 'css', 'logo', 'image'], agent: 'tzayar' },
  { keywords: ['research', 'מחקר', 'investigate', 'best practice'], agent: 'researcher' },
  { keywords: ['test', 'בדיקה', 'qa', 'e2e', 'regression'], agent: 'bodek' },
  { keywords: ['data', 'דאטא', 'mongo', 'sql', 'migration', 'db'], agent: 'data' },
  { keywords: ['debug', 'דיבאג', 'error', 'log', 'profiling'], agent: 'debugger' },
  { keywords: ['docker', 'container', 'k8s', 'devops'], agent: 'docker' },
  { keywords: ['frontend', 'html', 'responsive', 'javascript'], agent: 'front' },
  { keywords: ['backend', 'express', 'server', 'middleware'], agent: 'back' },
];

function ensureDir() {
  if (!fs.existsSync(CONSULT_DIR)) fs.mkdirSync(CONSULT_DIR, { recursive: true });
}

function consultPath(id) {
  return path.join(CONSULT_DIR, `${id}.json`);
}

function generateId() {
  return `consult-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function getEmoji(agent) {
  return AGENT_EMOJIS[agent] || '🤖';
}

function sendToAgentChat(agentId, message) {
  try {
    const target = getAgentChatTopic();
    execSync(`bash "${SEND_SH}" "${agentId}" "${target}" "${message.replace(/"/g, '\\"')}"`, {
      encoding: 'utf8', timeout: 15000, stdio: 'pipe'
    });
    return true;
  } catch (e) {
    return false;
  }
}

/**
 * Auto-route: given a question, determine which agent should answer.
 */
function autoRoute(question) {
  const lower = question.toLowerCase();
  for (const rule of ROUTING_RULES) {
    if (rule.keywords.some(kw => lower.includes(kw))) {
      return rule.agent;
    }
  }
  return null;
}

/**
 * Request help from another agent.
 */
function requestHelp(fromAgent, toAgent, threadId, question) {
  ensureDir();

  // Auto-route if toAgent not specified
  if (!toAgent) {
    toAgent = autoRoute(question) || 'worker';
  }

  const id = generateId();
  const consultation = {
    id,
    fromAgent,
    toAgent,
    threadId,
    question,
    status: 'pending',
    answer: null,
    createdAt: new Date().toISOString(),
    answeredAt: null
  };

  fs.writeFileSync(consultPath(id), JSON.stringify(consultation, null, 2));

  const message = `[${getEmoji(fromAgent)} ${fromAgent}] → [${getEmoji(toAgent)} ${toAgent}] | TYPE: consultation\n\n🆘 Thread #${threadId}\n${question}`;
  sendToAgentChat(fromAgent, message);

  return consultation;
}

/**
 * Respond to a help request.
 */
function respondToHelp(consultationId, fromAgent, answer) {
  ensureDir();
  const p = consultPath(consultationId);
  if (!fs.existsSync(p)) throw new Error(`Consultation not found: ${consultationId}`);

  const consultation = JSON.parse(fs.readFileSync(p, 'utf8'));
  consultation.status = 'answered';
  consultation.answer = answer;
  consultation.answeredAt = new Date().toISOString();
  fs.writeFileSync(p, JSON.stringify(consultation, null, 2));

  const message = `[${getEmoji(fromAgent)} ${fromAgent}] → [${getEmoji(consultation.fromAgent)} ${consultation.fromAgent}] | TYPE: consultation-response\n\n✅ Re: ${consultation.question.slice(0, 80)}...\n${answer}`;
  sendToAgentChat(fromAgent, message);

  return consultation;
}

/**
 * Get all pending (unanswered) consultations, optionally filtered by agent.
 */
function getPendingConsultations(forAgent) {
  ensureDir();
  const files = fs.readdirSync(CONSULT_DIR).filter(f => f.endsWith('.json'));
  const pending = [];
  for (const f of files) {
    try {
      const c = JSON.parse(fs.readFileSync(path.join(CONSULT_DIR, f), 'utf8'));
      if (c.status === 'pending') {
        if (!forAgent || c.toAgent === forAgent) pending.push(c);
      }
    } catch (_) {}
  }
  return pending;
}

/**
 * Get all consultations (any status).
 */
function getAllConsultations() {
  ensureDir();
  const files = fs.readdirSync(CONSULT_DIR).filter(f => f.endsWith('.json'));
  return files.map(f => {
    try { return JSON.parse(fs.readFileSync(path.join(CONSULT_DIR, f), 'utf8')); }
    catch (_) { return null; }
  }).filter(Boolean);
}

module.exports = {
  requestHelp,
  respondToHelp,
  getPendingConsultations,
  getAllConsultations,
  autoRoute,
  AGENT_EMOJIS,
  AGENT_CHAT_TOPIC: getAgentChatTopic
};
