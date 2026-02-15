const express = require('express');
const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar');

const app = express();
const PORT = 8090;
const SWARM = path.join(__dirname, '..');
const TASKS_FILE = path.join(SWARM, 'tasks.json');
const TASKS_DIR = path.join(SWARM, 'tasks');
const AGENTS_FILE = path.join(SWARM, 'agents.json');
const LOGS_DIR = path.join(SWARM, 'logs');
const SCORES_FILE = path.join(SWARM, 'learning', 'scores.json');
const LESSONS_FILE = path.join(SWARM, 'learning', 'lessons.json');

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

chokidar.watch([TASKS_FILE, TASKS_DIR, AGENTS_FILE, LOGS_DIR, SCORES_FILE, LESSONS_FILE], {
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

// API: task files (*.md from tasks dir)
app.get('/api/task-files', (req, res) => {
  try {
    if (!fs.existsSync(TASKS_DIR)) return res.json([]);
    const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.md'));
    const tasks = files.map(f => {
      const content = fs.readFileSync(path.join(TASKS_DIR, f), 'utf8');
      const id = f.replace('.md', '');
      const lines = content.split('\n');
      // Parse frontmatter-style fields
      const get = (label) => {
        const line = lines.find(l => l.toLowerCase().includes(`**${label}**`));
        if (line) { const m = line.match(/\*\*[^*]+\*\*[:\s]*(.+)/); return m ? m[1].trim() : ''; }
        return '';
      };
      const title = (lines[0] || '').replace(/^#\s*/, '').replace(/Task[:\s]*\d*\s*[—-]*\s*/i, '').trim();
      return {
        id,
        title: title || id,
        agent: get('agent') || get('Agent') || '',
        status: (get('status') || get('Status') || 'active').toLowerCase().replace(/[^a-z]/g,''),
        priority: (get('priority') || get('Priority') || 'normal').toLowerCase().replace(/[^a-z]/g,''),
        topic: get('topic') || get('Topic') || id,
        preview: lines.slice(0, 8).join('\n'),
        mtime: fs.statSync(path.join(TASKS_DIR, f)).mtime.toISOString()
      };
    });
    res.json(tasks);
  } catch (e) { res.json([]); }
});

// API: timeline — task events from logs
app.get('/api/timeline', (req, res) => {
  try {
    const events = [];
    const logFiles = fs.readdirSync(LOGS_DIR).filter(f => f.endsWith('.jsonl')).sort().reverse().slice(0, 7);
    for (const f of logFiles) {
      const lines = fs.readFileSync(path.join(LOGS_DIR, f), 'utf8').split('\n').filter(Boolean);
      for (const line of lines) {
        try {
          const entry = JSON.parse(line);
          events.push({
            timestamp: entry.timestamp || entry.ts,
            agent: entry.agent || entry.from || 'unknown',
            thread: entry.thread || entry.threadId || 0,
            action: entry.action || 'message',
            message: (entry.message || entry.text || '').substring(0, 200)
          });
        } catch (e) {}
      }
    }
    // Sort by time, return last 200
    events.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    res.json(events.slice(0, 200));
  } catch (e) { res.json([]); }
});

// API: quality scores
app.get('/api/quality', (req, res) => {
  try {
    const QUALITY_FILE = path.join(SWARM, 'learning', 'quality.json');
    const data = JSON.parse(fs.readFileSync(QUALITY_FILE, 'utf8'));
    res.json(data);
  } catch (e) { res.json({ reviews: [], agentAverages: {} }); }
});

// API: active context
app.get('/api/active-context', (req, res) => {
  try {
    const content = fs.readFileSync(path.join(SWARM, 'memory', 'shared', 'active-context.md'), 'utf8');
    res.json({ content });
  } catch (e) { res.json({ content: 'No active context' }); }
});

// API: scores
app.get('/api/scores', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(SCORES_FILE, 'utf8'));
    res.json(data.agents || {});
  } catch (e) { res.json({}); }
});

// API: lessons
app.get('/api/lessons', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(LESSONS_FILE, 'utf8'));
    res.json(data.lessons || []);
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
