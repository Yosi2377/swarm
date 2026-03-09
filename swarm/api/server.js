const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = 9200;

const TASKS_DIR = '/tmp/agent-tasks';
const DONE_DIR = '/tmp/agent-done';
const SCORES_FILE = path.resolve(__dirname, '..', 'data', 'scores.json');
const API_KEY_FILE = path.join(__dirname, '.api-key');

// --- API Key ---
function getOrCreateApiKey() {
  if (fs.existsSync(API_KEY_FILE)) {
    return fs.readFileSync(API_KEY_FILE, 'utf8').trim();
  }
  const key = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(API_KEY_FILE, key, { mode: 0o600 });
  return key;
}
const API_KEY = getOrCreateApiKey();

// --- Rate Limiting ---
const rateLimits = new Map();
const RATE_LIMIT = 500;
const RATE_WINDOW = 60000; // 1 minute

function rateLimit(req, res, next) {
  const ip = req.ip || req.connection.remoteAddress;
  const now = Date.now();
  let entry = rateLimits.get(ip);
  if (!entry || now - entry.start > RATE_WINDOW) {
    entry = { start: now, count: 0 };
    rateLimits.set(ip, entry);
  }
  entry.count++;
  if (entry.count > RATE_LIMIT) {
    return res.status(429).json({ error: 'Too many requests' });
  }
  next();
}

// Cleanup old rate limit entries every 5 min
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of rateLimits) {
    if (now - entry.start > RATE_WINDOW) rateLimits.delete(ip);
  }
}, 300000);

// --- Auth Middleware ---
function requireAuth(req, res, next) {
  const key = req.headers['x-api-key'] || req.query.key;
  if (!key || key !== API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// --- CORS ---
const ALLOWED_ORIGINS = (process.env.CORS_ORIGINS || '').split(',').filter(Boolean);

function corsMiddleware(req, res, next) {
  const origin = req.headers.origin;
  if (ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin || '*');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,X-API-Key');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
}

// --- Input Sanitizer ---
function sanitize(str) {
  if (typeof str !== 'string') return str;
  return str.replace(/[<>&"']/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&#39;' }[c]));
}

// --- Middleware ---
app.use(corsMiddleware);
app.use(rateLimit);
app.use(express.json());

// --- Helpers ---

function readJsonFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => f.endsWith('.json'))
    .map(f => {
      try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); }
      catch { return null; }
    })
    .filter(Boolean);
}

function loadScores() {
  try { return JSON.parse(fs.readFileSync(SCORES_FILE, 'utf8')); }
  catch { return {}; }
}

function getAllTasks() {
  const tasks = readJsonFiles(TASKS_DIR);
  const done = readJsonFiles(DONE_DIR);
  const doneMap = {};
  done.forEach(d => { if (d.taskId) doneMap[d.taskId] = d; });
  return tasks.map(t => {
    const id = t.id || t.taskId || `${t.agentId}-${t.threadId}`;
    const d = doneMap[id];
    return {
      id,
      agentId: t.agentId || t.agent || 'unknown',
      description: t.description || t.input?.description || t.task || '',
      status: d ? (d.status || 'passed') : (t.status || t.state || 'queued'),
      created: t.created || t.timestamp || t.metadata?.created || null,
      completed: d?.completed || d?.timestamp || null,
      contract: t.contract || t,
      history: t.history || [],
      retries: t.retries || t.retryCount || 0
    };
  });
}

// --- Public Routes ---

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime(), timestamp: new Date().toISOString() });
});

// --- Protected Routes ---

app.get('/api/tasks', requireAuth, (req, res) => {
  res.json(getAllTasks());
});

app.get('/api/tasks/:id', requireAuth, (req, res) => {
  const task = getAllTasks().find(t => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'Task not found' });
  res.json(task);
});

app.get('/api/agents', requireAuth, (req, res) => {
  const scores = loadScores();
  const tasks = getAllTasks();
  const agentMap = {};
  const AGENTS = [
    { id: 'shomer', name: 'שומר', emoji: '🔒' },
    { id: 'koder', name: 'קודר', emoji: '⚙️' },
    { id: 'tzayar', name: 'צייר', emoji: '🎨' },
    { id: 'researcher', name: 'חוקר', emoji: '🔍' },
    { id: 'bodek', name: 'בודק', emoji: '🧪' },
    { id: 'data', name: 'דאטא', emoji: '📊' },
    { id: 'debugger', name: 'דיבאגר', emoji: '🐛' },
    { id: 'docker', name: 'דוקר', emoji: '🐳' },
    { id: 'front', name: 'פרונט', emoji: '🖥️' },
    { id: 'back', name: 'באק', emoji: '⚡' },
    { id: 'worker', name: 'עובד', emoji: '🤖' },
  ];
  AGENTS.forEach(a => {
    const agentTasks = tasks.filter(t => t.agentId === a.id);
    agentMap[a.id] = {
      ...a,
      score: scores[a.id] || 0,
      totalTasks: agentTasks.length,
      activeTasks: agentTasks.filter(t => ['queued','running','verifying'].includes(t.status)).length
    };
  });
  res.json(Object.values(agentMap));
});

app.get('/api/stats', requireAuth, (req, res) => {
  const tasks = getAllTasks();
  const total = tasks.length;
  const passed = tasks.filter(t => t.status === 'passed').length;
  const failed = tasks.filter(t => t.status?.startsWith('failed')).length;
  const retried = tasks.filter(t => t.retries > 0).length;
  const completed = tasks.filter(t => t.completed && t.created);
  let avgTime = 0;
  if (completed.length) {
    const times = completed.map(t => new Date(t.completed) - new Date(t.created)).filter(t => t > 0);
    avgTime = times.length ? Math.round(times.reduce((a,b) => a+b, 0) / times.length / 1000) : 0;
  }
  const active = tasks.filter(t => ['queued','running','verifying'].includes(t.status)).length;
  res.json({
    totalTasks: total,
    passRate: total ? Math.round(passed / total * 100) : 0,
    failRate: total ? Math.round(failed / total * 100) : 0,
    retryRate: total ? Math.round(retried / total * 100) : 0,
    avgCompletionTime: avgTime,
    activeAgents: new Set(tasks.filter(t => ['running','verifying'].includes(t.status)).map(t => t.agentId)).size,
    activeTasks: active
  });
});

app.post('/api/tasks', requireAuth, (req, res) => {
  const { description, agentId, projectId } = req.body || {};
  // Validate description
  if (!description || typeof description !== 'string') {
    return res.status(400).json({ error: 'description required (string, 1-1000 chars)' });
  }
  const trimmed = description.trim();
  if (trimmed.length < 1 || trimmed.length > 1000) {
    return res.status(400).json({ error: 'description must be 1-1000 characters' });
  }
  const safeDesc = sanitize(trimmed);
  const safeAgent = sanitize(agentId || 'worker');

  const id = `${safeAgent}-${Date.now()}`;
  const task = {
    id,
    agentId: safeAgent,
    description: safeDesc,
    projectId: projectId ? sanitize(String(projectId)) : null,
    status: 'queued',
    created: new Date().toISOString(),
    retries: 0,
    history: [],
    contract: { id, type: 'code', input: { description: safeDesc } }
  };
  if (!fs.existsSync(TASKS_DIR)) fs.mkdirSync(TASKS_DIR, { recursive: true });
  fs.writeFileSync(path.join(TASKS_DIR, `${id}.json`), JSON.stringify(task, null, 2));
  res.status(201).json(task);
});

app.post('/api/tasks/:id/retry', requireAuth, (req, res) => {
  const tasks = getAllTasks();
  const task = tasks.find(t => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'Task not found' });
  const fp = path.join(TASKS_DIR, `${task.id}.json`);
  if (fs.existsSync(fp)) {
    const data = JSON.parse(fs.readFileSync(fp, 'utf8'));
    data.status = 'queued';
    data.retries = (data.retries || 0) + 1;
    data.history = data.history || [];
    data.history.push({ event: 'manual_retry', timestamp: new Date().toISOString() });
    fs.writeFileSync(fp, JSON.stringify(data, null, 2));
    res.json({ ...data, message: 'Task queued for retry' });
  } else {
    res.status(404).json({ error: 'Task file not found' });
  }
});

// Serve dashboard (requires key as query param)
app.get('/', requireAuth, (req, res) => {
  let html = fs.readFileSync(path.join(__dirname, 'dashboard.html'), 'utf8');
  // Inject API key into dashboard
  html = html.replace('</h1>', `</h1>\n<div class="api-key-bar">🔑 API Key: <code id="apikey">${API_KEY}</code> <button onclick="navigator.clipboard.writeText(document.getElementById('apikey').textContent)">📋</button></div>`);
  // Inject key constant and replace fetch calls to pass it
  html = html.replace(
    "async function refresh(){",
    `const _KEY='${API_KEY}';\nasync function refresh(){`
  );
  res.type('html').send(html);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🐝 Swarm API running on port ${PORT}`);
  console.log(`🔑 API Key: ${API_KEY}`);
});

module.exports = app;
