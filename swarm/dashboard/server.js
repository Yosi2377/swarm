const express = require('express');
const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar');

const app = express();
const PORT = 8090;
const SWARM = path.join(__dirname, '..');
const TASKS_FILE = path.join(SWARM, 'tasks.json');
const AGENTS_FILE = path.join(SWARM, 'agents.json');
const LOGS_DIR = path.join(SWARM, 'logs');

// SSE clients
let sseClients = [];

// Watch for changes with debounce
let notifyTimeout = null;
function notifyClients() {
  if (notifyTimeout) return;
  notifyTimeout = setTimeout(() => {
    notifyTimeout = null;
    sseClients.forEach(res => {
      try { res.write(`data: update\n\n`); } catch(e) {}
    });
  }, 300);
}

chokidar.watch([TASKS_FILE, AGENTS_FILE, LOGS_DIR], {
  ignoreInitial: true,
  usePolling: true,
  interval: 1000,
  awaitWriteFinish: { stabilityThreshold: 500, pollInterval: 200 }
}).on('all', notifyClients);

app.use(express.static(path.join(__dirname, 'public')));

// API: agents
app.get('/api/agents', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(AGENTS_FILE, 'utf8'));
    res.json(data.agents || {});
  } catch (e) { res.json({}); }
});

// API: tasks
app.get('/api/tasks', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8'));
    res.json(data);
  } catch (e) { res.json({ tasks: [], completed: [] }); }
});

// API: logs (today + optional date param)
app.get('/api/logs', (req, res) => {
  try {
    const date = req.query.date || new Date().toISOString().slice(0, 10);
    const file = path.join(LOGS_DIR, `${date}.jsonl`);
    if (!fs.existsSync(file)) return res.json([]);
    const content = fs.readFileSync(file, 'utf8').trim();
    // JSONL where each entry may be pretty-printed (multi-line JSON objects)
    const entries = [];
    let depth = 0, start = -1;
    for (let i = 0; i < content.length; i++) {
      if (content[i] === '{') { if (depth === 0) start = i; depth++; }
      else if (content[i] === '}') { depth--; if (depth === 0 && start >= 0) {
        try { entries.push(JSON.parse(content.slice(start, i + 1))); } catch {}
        start = -1;
      }}
    }
    res.json(entries);
  } catch (e) { res.json([]); }
});

// API: log dates available
app.get('/api/log-dates', (req, res) => {
  try {
    const files = fs.readdirSync(LOGS_DIR).filter(f => f.endsWith('.jsonl')).sort().reverse();
    res.json(files.map(f => f.replace('.jsonl', '')));
  } catch (e) { res.json([]); }
});

// SSE endpoint
app.get('/api/events', (req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' });
  res.write(`data: connected\n\n`);
  sseClients.push(res);
  req.on('close', () => { sseClients = sseClients.filter(c => c !== res); });
});

// SSE keepalive heartbeat every 30s
setInterval(() => {
  sseClients.forEach(res => {
    try { res.write(`:heartbeat\n\n`); } catch(e) {}
  });
}, 30000);

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Swarm Dashboard running on port ${PORT}`);
});
