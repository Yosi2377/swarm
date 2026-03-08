const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 9200;

const TASKS_DIR = '/tmp/agent-tasks';
const DONE_DIR = '/tmp/agent-done';
const SCORES_FILE = path.resolve(__dirname, '..', 'data', 'scores.json');

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

// --- Routes ---

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime(), timestamp: new Date().toISOString() });
});

app.get('/api/tasks', (req, res) => {
  res.json(getAllTasks());
});

app.get('/api/tasks/:id', (req, res) => {
  const task = getAllTasks().find(t => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'Task not found' });
  res.json(task);
});

app.get('/api/agents', (req, res) => {
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

app.get('/api/stats', (req, res) => {
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

app.post('/api/tasks', (req, res) => {
  const { description, agentId, projectId } = req.body || {};
  if (!description) return res.status(400).json({ error: 'description required' });
  const id = `${agentId || 'worker'}-${Date.now()}`;
  const task = {
    id,
    agentId: agentId || 'worker',
    description,
    projectId: projectId || null,
    status: 'queued',
    created: new Date().toISOString(),
    retries: 0,
    history: [],
    contract: { id, type: 'code', input: { description } }
  };
  if (!fs.existsSync(TASKS_DIR)) fs.mkdirSync(TASKS_DIR, { recursive: true });
  fs.writeFileSync(path.join(TASKS_DIR, `${id}.json`), JSON.stringify(task, null, 2));
  res.status(201).json(task);
});

app.post('/api/tasks/:id/retry', (req, res) => {
  const tasks = getAllTasks();
  const task = tasks.find(t => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'Task not found' });
  // Update status to queued for retry
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

// Serve dashboard
app.get('/', (req, res) => {
  const html = fs.readFileSync(path.join(__dirname, 'dashboard.html'), 'utf8');
  res.type('html').send(html);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🐝 Swarm API running on port ${PORT}`);
});

module.exports = app;
