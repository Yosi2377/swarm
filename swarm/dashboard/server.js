const express = require('express');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const chokidar = require('chokidar');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });
const PORT = 8090;
const START_TIME = Date.now();
const SWARM = path.join(__dirname, '..');
const TASKS_FILE = path.join(SWARM, 'tasks.json');
const TASKS_DIR = path.join(SWARM, 'tasks');
const AGENTS_FILE = path.join(SWARM, 'agents.json');
const LOGS_DIR = path.join(SWARM, 'logs');
const SCORES_FILE = path.join(SWARM, 'learning', 'scores.json');
const LESSONS_FILE = path.join(SWARM, 'learning', 'lessons.json');
const ACTIVE_CONTEXT = path.join(SWARM, 'memory', 'shared', 'active-context.md');

// SSE clients
let sseClients = [];

// Socket.io connections
io.on('connection', (socket) => {
  socket.emit('update', { type: 'connected', ts: Date.now() });
});

// Watch for changes with debounce — notify SSE + socket.io
let notifyTimeout = null;
function notifyClients(eventType) {
  if (notifyTimeout) return;
  notifyTimeout = setTimeout(() => {
    notifyTimeout = null;
    const data = { type: eventType || 'update', ts: Date.now() };
    const dataStr = JSON.stringify(data);
    // SSE
    sseClients.forEach(res => {
      try { res.write(`data: ${dataStr}\n\n`); } catch(e) {}
    });
    // Socket.io — emit specific event + generic update
    io.emit('update', data);
    const eventMap = { tasks: 'taskUpdate', agents: 'agentUpdate', scores: 'scoreUpdate', lessons: 'lessonUpdate', live: 'agentUpdate', timeline: 'taskUpdate' };
    if (eventMap[eventType]) io.emit(eventMap[eventType], data);
  }, 300);
}

chokidar.watch([TASKS_FILE, TASKS_DIR, AGENTS_FILE, LOGS_DIR, SCORES_FILE, LESSONS_FILE, ACTIVE_CONTEXT], {
  ignoreInitial: true,
  usePolling: true,
  interval: 1000,
  awaitWriteFinish: { stabilityThreshold: 500, pollInterval: 200 }
}).on('all', (event, filePath) => {
  const type = filePath.includes('tasks') ? 'tasks' :
               filePath.includes('active-context') ? 'agents' :
               filePath.includes('scores') ? 'scores' :
               filePath.includes('lessons') ? 'lessons' :
               filePath.includes('logs') ? 'timeline' : 'update';
  notifyClients(type);
});

app.use(express.static(path.join(__dirname, 'public')));

// Sessions file path
const SESSIONS_JSON = '/root/.openclaw/agents/main/sessions/sessions.json';
const SESSIONS_DIR = '/root/.openclaw/agents/main/sessions';

// Agent ID mapping from session keys
const AGENT_MAP = {
  'or': { name: 'אור', emoji: '✨', role: 'orchestrator' },
  'shomer': { name: 'שומר', emoji: '🔒', role: 'security' },
  'koder': { name: 'קודר', emoji: '⚙️', role: 'coding' },
  'tzayar': { name: 'צייר', emoji: '🎨', role: 'design' },
  'worker': { name: 'עובד', emoji: '🤖', role: 'worker' },
  'researcher': { name: 'חוקר', emoji: '🔍', role: 'research' }
};

// Map topic IDs to agents from tasks.json
function getTopicAgentMap() {
  try {
    const data = JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8'));
    const map = {};
    for (const t of (data.tasks || [])) {
      if (t.thread && t.agent) map[String(t.thread)] = { agent: t.agent, title: t.title || '' };
    }
    return map;
  } catch { return {}; }
}

// API: live sessions from sessions.json
app.get('/api/agents/live', (req, res) => {
  try {
    const sessData = JSON.parse(fs.readFileSync(SESSIONS_JSON, 'utf8'));
    const topicMap = getTopicAgentMap();
    const now = Date.now();
    const results = [];

    for (const [key, meta] of Object.entries(sessData)) {
      const updatedAt = meta.updatedAt || 0;
      const ageMin = (now - updatedAt) / 60000;
      const status = ageMin < 2 ? 'active' : ageMin < 10 ? 'recent' : 'idle';

      // Parse session key
      const isSubagent = key.includes(':subagent:');
      const topicMatch = key.match(/:topic:(\d+)$/);
      const topicId = topicMatch ? topicMatch[1] : null;

      // Determine identity
      let agentId = null, agentName = key, emoji = '🔵', role = '', currentTask = '';

      if (isSubagent) {
        const subId = key.split(':subagent:')[1] || '';
        agentName = meta.label || `sub-${subId.slice(0, 8)}`;
        emoji = '🔄';
        role = 'sub-agent';
        currentTask = meta.label || '';
      } else if (topicId) {
        const taskInfo = topicMap[topicId];
        if (taskInfo && AGENT_MAP[taskInfo.agent]) {
          agentId = taskInfo.agent;
          agentName = AGENT_MAP[taskInfo.agent].name;
          emoji = AGENT_MAP[taskInfo.agent].emoji;
          role = AGENT_MAP[taskInfo.agent].role;
          currentTask = taskInfo.title;
        } else if (topicId === '1') {
          agentId = 'or';
          agentName = 'אור';
          emoji = '✨';
          role = 'orchestrator';
          currentTask = 'General';
        } else {
          agentName = `topic-${topicId}`;
          emoji = '💬';
        }
      } else if (key === 'agent:main:main') {
        agentId = 'main';
        agentName = 'Main Session';
        emoji = '🏠';
        role = 'main';
      }

      // Only include recently active sessions (last 30 min) or subagents (last 60 min)
      const maxAge = isSubagent ? 60 : 30;
      if (ageMin > maxAge) continue;

      results.push({
        key,
        agentId,
        name: agentName,
        emoji,
        role,
        type: isSubagent ? 'subagent' : 'agent',
        status,
        currentTask,
        topic: topicId ? parseInt(topicId) : null,
        model: meta.model || '',
        lastActive: new Date(updatedAt).toISOString(),
        ageMinutes: Math.round(ageMin),
        tokens: meta.totalTokens || 0,
        spawnedBy: meta.spawnedBy || null
      });
    }

    // Sort: active first, then by recency
    results.sort((a, b) => {
      const order = { active: 0, recent: 1, idle: 2 };
      return (order[a.status] - order[b.status]) || (a.ageMinutes - b.ageMinutes);
    });

    res.json(results);
  } catch (e) {
    res.json([]);
  }
});

// Watch sessions.json for SSE
chokidar.watch(SESSIONS_JSON, {
  ignoreInitial: true, usePolling: true, interval: 2000,
  awaitWriteFinish: { stabilityThreshold: 500, pollInterval: 200 }
}).on('all', () => notifyClients('live'));

// Helper: parse task md file
function parseTaskMd(filepath, id) {
  try {
    const content = fs.readFileSync(filepath, 'utf8');
    const lines = content.split('\n');
    const get = (label) => {
      const line = lines.find(l => l.toLowerCase().includes(`**${label.toLowerCase()}**`));
      if (line) { const m = line.match(/\*\*[^*]+\*\*[:\s]*(.+)/); return m ? m[1].trim() : ''; }
      return '';
    };
    const title = (lines[0] || '').replace(/^#\s*/, '').replace(/Task[:\s]*\d*\s*[—-]*\s*/i, '').trim();
    return {
      id,
      title: title || id,
      agent: get('agent') || get('Agent') || '',
      status: (get('status') || get('Status') || 'active').toLowerCase().replace(/[^a-z]/g, ''),
      priority: (get('priority') || get('Priority') || 'normal').toLowerCase().replace(/[^a-z]/g, ''),
      topic: get('topic') || get('Topic') || id,
      preview: lines.slice(0, 8).join('\n'),
      mtime: fs.statSync(filepath).mtime.toISOString(),
      source: 'file'
    };
  } catch (e) { return null; }
}

// API: tasks — merged from tasks.json + tasks/*.md
app.get('/api/tasks', (req, res) => {
  try {
    // Load tasks.json
    let jsonData = { tasks: [], completed: [] };
    try { jsonData = JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8')); } catch (e) {}

    // Load task md files
    const mdTasks = {};
    if (fs.existsSync(TASKS_DIR)) {
      const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.md'));
      for (const f of files) {
        const id = f.replace('.md', '');
        const parsed = parseTaskMd(path.join(TASKS_DIR, f), id);
        if (parsed) mdTasks[id] = parsed;
      }
    }

    // Merge: tasks.json entries enriched with md data
    const activeIds = new Set();
    const completedIds = new Set();

    const active = (jsonData.tasks || []).map(t => {
      const id = String(t.id || t.thread);
      activeIds.add(id);
      const md = mdTasks[id];
      return { ...t, ...(md ? { title: md.title || t.title, preview: md.preview, mdStatus: md.status, mdAgent: md.agent } : {}), source: 'merged' };
    });

    const completed = (jsonData.completed || []).map(t => {
      const id = String(t.id || t.thread);
      completedIds.add(id);
      const md = mdTasks[id];
      return { ...t, ...(md ? { title: md.title || t.title, preview: md.preview } : {}), source: 'merged' };
    });

    // Add md-only tasks not in tasks.json
    for (const [id, md] of Object.entries(mdTasks)) {
      if (!activeIds.has(id) && !completedIds.has(id)) {
        if (md.status === 'done' || md.status === 'completed') {
          completed.push(md);
        } else {
          active.push(md);
        }
      }
    }

    res.json({ tasks: active, completed });
  } catch (e) { res.json({ tasks: [], completed: [] }); }
});

// API: agents — merged from agents.json + active-context.md + scores.json
app.get('/api/agents', (req, res) => {
  try {
    // 1. Load agent definitions from agents.json
    let agentDefs = {};
    try {
      const data = JSON.parse(fs.readFileSync(AGENTS_FILE, 'utf8'));
      agentDefs = data.agents || {};
    } catch (e) {}

    // 2. Parse active-context.md for live status
    const contextStatus = {}; // map Hebrew name -> { status, task, thread, lastUpdate }
    try {
      const content = fs.readFileSync(ACTIVE_CONTEXT, 'utf8');
      for (const line of content.split('\n')) {
        const match = line.match(/^\|\s*([^\|]+)\|\s*([^\|]+)\|\s*([^\|]+)\|\s*([^\|]+)\|\s*([^\|]+)\|/);
        if (!match) continue;
        const name = match[1].trim();
        if (name === 'סוכן' || name.startsWith('---')) continue;
        const emojiMatch = name.match(/^(.+?)\s+(.+)$/);
        const agentName = emojiMatch ? emojiMatch[2].trim() : name;
        contextStatus[agentName] = {
          status: match[2].trim(),
          task: match[3].trim(),
          thread: match[4].trim(),
          lastUpdate: match[5].trim()
        };
      }
    } catch (e) {}

    // 3. Load scores
    let scores = {};
    try {
      scores = JSON.parse(fs.readFileSync(SCORES_FILE, 'utf8')).agents || {};
    } catch (e) {}

    // 4. Merge everything, keyed by agent ID
    const result = {};
    for (const [id, def] of Object.entries(agentDefs)) {
      const ctx = contextStatus[def.name] || {};
      const score = scores[id] || {};
      const isActive = ctx.status === 'active' || ctx.status === 'working' || ctx.status === 'פעיל';
      const isStuck = ctx.status === 'stuck' || ctx.status === 'תקוע';
      result[id] = {
        name: def.name,
        emoji: def.emoji,
        role: def.role,
        status: isStuck ? 'stuck' : isActive ? 'active' : 'idle',
        task: (ctx.task && ctx.task !== '—') ? ctx.task : null,
        thread: (ctx.thread && ctx.thread !== '—') ? ctx.thread : null,
        lastUpdate: (ctx.lastUpdate && ctx.lastUpdate !== '—') ? ctx.lastUpdate : null,
        score: score.score ?? null,
        tasks: score.tasks ?? 0,
        success: score.success ?? 0,
        fail: score.fail ?? 0,
        streak: score.streak ?? 0
      };
    }

    res.json(result);
  } catch (e) {
    try {
      const data = JSON.parse(fs.readFileSync(AGENTS_FILE, 'utf8'));
      res.json(data.agents || {});
    } catch (e2) { res.json({}); }
  }
});

// API: timeline — git log + task events + lessons
app.get('/api/timeline', (req, res) => {
  try {
    const events = [];

    // 1. Git log (last 50 commits)
    try {
      const gitLog = execSync('git log --format="%H|%an|%ai|%s" -50 2>/dev/null', { cwd: SWARM, encoding: 'utf8', timeout: 5000 });
      for (const line of gitLog.trim().split('\n').filter(Boolean)) {
        const [hash, author, date, ...msgParts] = line.split('|');
        events.push({
          type: 'git',
          timestamp: date,
          agent: author || 'git',
          message: msgParts.join('|'),
          hash: (hash || '').substring(0, 8)
        });
      }
    } catch (e) {}

    // 2. Log entries (last 7 days)
    try {
      const logFiles = fs.readdirSync(LOGS_DIR).filter(f => f.endsWith('.jsonl')).sort().reverse().slice(0, 7);
      for (const f of logFiles) {
        const content = fs.readFileSync(path.join(LOGS_DIR, f), 'utf8');
        // Handle both strict JSONL and pretty-printed JSON
        const entries = [];
        let depth = 0, start = -1;
        for (let i = 0; i < content.length; i++) {
          if (content[i] === '{') { if (depth === 0) start = i; depth++; }
          else if (content[i] === '}') { depth--; if (depth === 0 && start >= 0) {
            try { entries.push(JSON.parse(content.slice(start, i + 1))); } catch {} start = -1;
          }}
        }
        for (const entry of entries) {
          events.push({
            type: 'log',
            timestamp: entry.timestamp || entry.ts,
            agent: entry.agent || entry.from || 'unknown',
            thread: entry.thread || entry.threadId || 0,
            message: (entry.message || entry.text || '').substring(0, 200)
          });
        }
      }
    } catch (e) {}

    // 3. Completed tasks
    try {
      const jsonData = JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8'));
      for (const t of (jsonData.completed || [])) {
        events.push({
          type: 'task_done',
          timestamp: t.completedAt || t.updatedAt,
          agent: t.agent || 'unknown',
          thread: t.thread,
          message: `✅ ${t.title || 'Task ' + t.id} completed`
        });
      }
    } catch (e) {}

    // 4. Lessons
    try {
      const lessonsData = JSON.parse(fs.readFileSync(LESSONS_FILE, 'utf8'));
      for (const l of (lessonsData.lessons || []).slice(-30)) {
        events.push({
          type: 'lesson',
          timestamp: l.timestamp || l.date,
          agent: l.agent || 'system',
          message: `📚 ${l.lesson || l.text || ''}`
        });
      }
    } catch (e) {}

    // Sort by time desc, return with limit
    events.sort((a, b) => new Date(b.timestamp || 0) - new Date(a.timestamp || 0));
    const limit = Math.min(parseInt(req.query.limit) || 200, 500);
    res.json(events.slice(0, limit));
  } catch (e) { res.json([]); }
});

// API: SSE stream
app.get('/api/stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  });
  res.write(`data: ${JSON.stringify({ type: 'connected', ts: Date.now() })}\n\n`);
  sseClients.push(res);
  req.on('close', () => { sseClients = sseClients.filter(c => c !== res); });
});

// Keep old /api/events for backward compat
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

// API: quality scores
app.get('/api/quality', (req, res) => {
  try {
    const QUALITY_FILE = path.join(SWARM, 'learning', 'quality.json');
    const data = JSON.parse(fs.readFileSync(QUALITY_FILE, 'utf8'));
    res.json(data);
  } catch (e) { res.json({ reviews: [], agentAverages: {} }); }
});

// API: active context (raw)
app.get('/api/active-context', (req, res) => {
  try {
    const content = fs.readFileSync(ACTIVE_CONTEXT, 'utf8');
    res.json({ content });
  } catch (e) { res.json({ content: 'No active context' }); }
});

// API: logs
app.get('/api/logs', (req, res) => {
  try {
    const date = req.query.date || new Date().toISOString().slice(0, 10);
    const file = path.join(LOGS_DIR, `${date}.jsonl`);
    if (!fs.existsSync(file)) return res.json([]);
    const content = fs.readFileSync(file, 'utf8').trim();
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

// API: log dates
app.get('/api/log-dates', (req, res) => {
  try {
    const files = fs.readdirSync(LOGS_DIR).filter(f => f.endsWith('.jsonl')).sort().reverse();
    res.json(files.map(f => f.replace('.jsonl', '')));
  } catch (e) { res.json([]); }
});

// API: task files (legacy endpoint)
app.get('/api/task-files', (req, res) => {
  try {
    if (!fs.existsSync(TASKS_DIR)) return res.json([]);
    const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.md'));
    const tasks = files.map(f => parseTaskMd(path.join(TASKS_DIR, f), f.replace('.md', ''))).filter(Boolean);
    res.json(tasks);
  } catch (e) { res.json([]); }
});

// API: agent history — task history for specific agent
app.get('/api/agents/:id/history', (req, res) => {
  try {
    const agentId = req.params.id;
    let jsonData = { tasks: [], completed: [] };
    try { jsonData = JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8')); } catch {}
    const all = [...(jsonData.tasks || []), ...(jsonData.completed || [])];
    const history = all.filter(t => t.agent === agentId).map(t => ({
      id: t.id || t.thread,
      title: t.title || `Task ${t.id || t.thread}`,
      status: t.status || (jsonData.completed.includes(t) ? 'done' : 'active'),
      thread: t.thread,
      completedAt: t.completedAt || null,
      createdAt: t.createdAt || null
    }));
    res.json(history);
  } catch (e) { res.json([]); }
});

// API: stats summary
app.get('/api/stats/summary', (req, res) => {
  try {
    let jsonData = { tasks: [], completed: [] };
    try { jsonData = JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8')); } catch {}
    let lessonsData = { lessons: [] };
    try { lessonsData = JSON.parse(fs.readFileSync(LESSONS_FILE, 'utf8')); } catch {}
    let scoresData = { agents: {} };
    try { scoresData = JSON.parse(fs.readFileSync(SCORES_FILE, 'utf8')); } catch {}

    const activeTasks = (jsonData.tasks || []).length;
    const completedTasks = (jsonData.completed || []).length;
    const totalTasks = activeTasks + completedTasks;

    // Calculate success rate from scores
    let totalSuccess = 0, totalFail = 0;
    for (const a of Object.values(scoresData.agents || {})) {
      totalSuccess += (a.success || 0);
      totalFail += (a.fail || 0);
    }
    const successRate = (totalSuccess + totalFail) > 0 ? Math.round((totalSuccess / (totalSuccess + totalFail)) * 100) : 0;

    res.json({
      totalTasks,
      activeTasks,
      completedTasks,
      successRate,
      totalLessons: (lessonsData.lessons || []).length,
      uptime: Math.floor((Date.now() - START_TIME) / 1000)
    });
  } catch (e) { res.json({ totalTasks: 0, activeTasks: 0, successRate: 0, totalLessons: 0, uptime: 0 }); }
});

// API: health
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', uptime: Math.floor((Date.now() - START_TIME) / 1000), version: '2.0' });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Swarm Dashboard v2.0 running on port ${PORT} (HTTP + WebSocket)`);
});
