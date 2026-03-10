// Task Management API — REST endpoints for /tmp/agent-tasks/*.json
// Integrates with swarm state machine, verify-task.sh, dispatch-task.sh

const express = require('express');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const TASKS_DIR = '/tmp/agent-tasks';
const SWARM_DIR = path.resolve(__dirname, '..');

function ensureDir() {
  if (!fs.existsSync(TASKS_DIR)) fs.mkdirSync(TASKS_DIR, { recursive: true });
}

function loadAllTasks() {
  ensureDir();
  const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.json') && !f.includes('.contract.') && !f.startsWith('tc-'));
  return files.map(f => {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(TASKS_DIR, f), 'utf8'));
      const taskId = f.replace('.json', '');
      // Merge task_state if present, or infer status
      const status = data.task_state?.status || data.status || 'unknown';
      const retryCount = data.task_state?.retryCount ?? data.retries ?? 0;
      const createdAt = data.task_state?.createdAt || data.dispatched_at || null;
      const updatedAt = data.task_state?.updatedAt || null;
      
      // Calculate runtime
      let runtimeMs = null;
      if (createdAt) {
        const start = typeof createdAt === 'number' ? createdAt : new Date(createdAt).getTime();
        const end = (status === 'passed' || status === 'cancelled' || status === 'failed_terminal')
          ? (updatedAt || Date.now()) : Date.now();
        runtimeMs = (typeof end === 'number' ? end : Date.now()) - start;
      }

      // Load contract if exists
      let contract = null;
      const contractFile = path.join(TASKS_DIR, `${taskId}.contract.json`);
      if (fs.existsSync(contractFile)) {
        try { contract = JSON.parse(fs.readFileSync(contractFile, 'utf8')); } catch {}
      }

      return {
        id: taskId,
        agent_id: data.agent_id || taskId.split('-')[0],
        thread_id: data.thread_id || taskId.split('-').slice(1).join('-'),
        task_desc: data.task_desc || '',
        status,
        retryCount,
        maxRetries: data.task_state?.maxRetries ?? 3,
        createdAt,
        updatedAt,
        runtimeMs,
        runtimeFormatted: runtimeMs ? formatDuration(runtimeMs) : null,
        project: data.project || null,
        project_dir: data.project_dir || null,
        contract_id: data.contract_id || null,
        stuck_flagged: data.stuck_flagged || false,
        contract: contract ? { criteria: contract.acceptance_criteria || contract.criteria || [] } : null,
        history: data.task_state?.history || []
      };
    } catch { return null; }
  }).filter(t => t && t.id && !t.id.includes('undefined'));
}

function formatDuration(ms) {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

function loadTask(taskId) {
  const p = path.join(TASKS_DIR, `${taskId}.json`);
  if (!fs.existsSync(p)) return null;
  const tasks = loadAllTasks();
  return tasks.find(t => t.id === taskId) || null;
}

function setupTaskAPI(app) {
  // GET /api/tasks/managed — list all tasks from /tmp/agent-tasks
  app.get('/api/tasks/managed', (req, res) => {
    try {
      const tasks = loadAllTasks();
      const statusFilter = req.query.status;
      const agentFilter = req.query.agent;
      let filtered = tasks;
      if (statusFilter) filtered = filtered.filter(t => t.status === statusFilter);
      if (agentFilter) filtered = filtered.filter(t => t.agent_id === agentFilter);
      filtered.sort((a, b) => {
        const aTime = typeof a.createdAt === 'number' ? a.createdAt : new Date(a.createdAt || 0).getTime();
        const bTime = typeof b.createdAt === 'number' ? b.createdAt : new Date(b.createdAt || 0).getTime();
        return bTime - aTime;
      });
      res.json({ tasks: filtered, total: filtered.length });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  // GET /api/tasks/managed/:id — get single task
  app.get('/api/tasks/managed/:id', (req, res) => {
    const task = loadTask(req.params.id);
    if (!task) return res.status(404).json({ error: 'Task not found' });
    res.json(task);
  });

  // POST /api/tasks/managed — create a new task
  app.use(express.json());
  app.post('/api/tasks/managed', (req, res) => {
    try {
      const { agent_id, thread_id, task_desc, project_dir, project } = req.body;
      if (!agent_id || !thread_id || !task_desc) {
        return res.status(400).json({ error: 'Missing required fields: agent_id, thread_id, task_desc' });
      }
      const taskId = `${agent_id}-${thread_id}`;
      const taskFile = path.join(TASKS_DIR, `${taskId}.json`);
      if (fs.existsSync(taskFile)) {
        return res.status(409).json({ error: 'Task already exists', id: taskId });
      }
      const now = Date.now();
      const taskData = {
        agent_id,
        thread_id: String(thread_id),
        task_desc,
        test_cmd: '',
        project_dir: project_dir || '',
        project: project || '',
        dispatched_at: new Date().toISOString(),
        status: 'queued',
        retries: 0,
        task_state: {
          taskId,
          contractId: null,
          status: 'queued',
          retryCount: 0,
          maxRetries: 3,
          history: [{ from: null, to: 'queued', reason: 'created via API', timestamp: now }],
          createdAt: now,
          updatedAt: now
        }
      };
      ensureDir();
      fs.writeFileSync(taskFile, JSON.stringify(taskData, null, 2));
      res.status(201).json({ id: taskId, status: 'queued', message: 'Task created' });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  // POST /api/tasks/managed/:id/retry — manual retry
  app.post('/api/tasks/managed/:id/retry', (req, res) => {
    try {
      const taskId = req.params.id;
      const taskFile = path.join(TASKS_DIR, `${taskId}.json`);
      if (!fs.existsSync(taskFile)) return res.status(404).json({ error: 'Task not found' });
      
      const data = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
      const status = data.task_state?.status || data.status;
      
      if (status === 'passed' || status === 'cancelled') {
        return res.status(400).json({ error: `Cannot retry task in ${status} state` });
      }

      const now = Date.now();
      if (!data.task_state) {
        data.task_state = { taskId, status: 'running', retryCount: 1, maxRetries: 3, history: [], createdAt: now, updatedAt: now };
      }
      data.task_state.history.push({ from: data.task_state.status, to: 'running', reason: 'manual retry via API', timestamp: now });
      data.task_state.status = 'running';
      data.task_state.retryCount = (data.task_state.retryCount || 0) + 1;
      data.task_state.updatedAt = now;
      data.status = 'running';
      data.retries = data.task_state.retryCount;
      data.stuck_flagged = false;

      fs.writeFileSync(taskFile, JSON.stringify(data, null, 2));
      res.json({ id: taskId, status: 'running', retryCount: data.task_state.retryCount, message: 'Task retried' });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  // POST /api/tasks/managed/:id/cancel — cancel task
  app.post('/api/tasks/managed/:id/cancel', (req, res) => {
    try {
      const taskId = req.params.id;
      const taskFile = path.join(TASKS_DIR, `${taskId}.json`);
      if (!fs.existsSync(taskFile)) return res.status(404).json({ error: 'Task not found' });
      
      const data = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
      const status = data.task_state?.status || data.status;
      
      if (status === 'cancelled') {
        return res.status(400).json({ error: 'Task already cancelled' });
      }

      const now = Date.now();
      if (!data.task_state) {
        data.task_state = { taskId, status: 'cancelled', retryCount: 0, maxRetries: 3, history: [], createdAt: now, updatedAt: now };
      }
      data.task_state.history.push({ from: data.task_state.status, to: 'cancelled', reason: req.body?.reason || 'cancelled via API', timestamp: now });
      data.task_state.status = 'cancelled';
      data.task_state.updatedAt = now;
      data.status = 'cancelled';

      fs.writeFileSync(taskFile, JSON.stringify(data, null, 2));
      res.json({ id: taskId, status: 'cancelled', message: 'Task cancelled' });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
}

module.exports = { setupTaskAPI, loadAllTasks, loadTask, formatDuration };
