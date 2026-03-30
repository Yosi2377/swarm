const fs = require('fs');
const path = require('path');

const SWARM_DIR = path.resolve(__dirname, '..');
const JOBS_DIR = path.join(SWARM_DIR, 'jobs');
const INDEX_FILE = path.join(JOBS_DIR, 'index.json');
const RUNTIME_FILE = path.join(SWARM_DIR, 'runtime.json');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

function runtimeConfig() {
  return readJson(RUNTIME_FILE, {
    transport: 'telegram',
    irc: { opsChannel: '#myops', jobChannelPrefix: '#job-', nick: 'Or_' },
    jobs: { defaultMode: 'ops', mirrorDoneToOps: true },
  });
}

function loadIndex() {
  ensureDir(JOBS_DIR);
  return readJson(INDEX_FILE, { nextId: 1 });
}

function saveIndex(index) {
  ensureDir(JOBS_DIR);
  writeJson(INDEX_FILE, index);
}

function jobFile(jobId) {
  return path.join(JOBS_DIR, `${jobId}.json`);
}

function loadJob(jobId) {
  const file = jobFile(jobId);
  if (!fs.existsSync(file)) {
    throw new Error(`Unknown job: ${jobId}`);
  }
  return readJson(file, null);
}

function saveJob(job) {
  ensureDir(JOBS_DIR);
  writeJson(jobFile(job.jobId), job);
}

function classifyMode(taskDescription) {
  const text = String(taskDescription || '').toLowerCase();
  if (!text.trim()) return runtimeConfig().jobs?.defaultMode || 'ops';
  const complexPatterns = [
    /,.*,/,
    /\b(review|research|investigate|audit|migrate|refactor|system|architecture|collab|debate|compare|multi-agent|security|docker|deployment|monitoring)\b/,
    /\b(api|backend|frontend|database|integration)\b.*\b(and|with)\b/,
  ];
  if (text.length > 180 || complexPatterns.some((re) => re.test(text))) {
    return 'dedicated';
  }
  return 'ops';
}

function channelFor(jobId, mode) {
  const cfg = runtimeConfig();
  if (mode === 'dedicated') {
    const prefix = cfg.irc?.jobChannelPrefix || '#job-';
    return `${prefix}${jobId.replace(/^job-/, '')}`;
  }
  return cfg.irc?.opsChannel || '#myops';
}

function timestamp() {
  return new Date().toISOString();
}

function appendHistory(job, event) {
  job.history = Array.isArray(job.history) ? job.history : [];
  job.history.push({ at: timestamp(), ...event });
  job.updatedAt = timestamp();
}

function createJob(title, agent, mode = 'ops') {
  const index = loadIndex();
  const numeric = index.nextId || 1;
  const jobId = `job-${String(numeric).padStart(4, '0')}`;
  index.nextId = numeric + 1;
  saveIndex(index);

  const job = {
    jobId,
    title,
    agent: agent || null,
    status: 'open',
    mode,
    channel: channelFor(jobId, mode),
    createdAt: timestamp(),
    updatedAt: timestamp(),
    history: [],
  };
  appendHistory(job, { type: 'created', title, agent: agent || null, mode, channel: job.channel });
  saveJob(job);
  return job;
}

function ensureChannel(jobId, taskDescription) {
  const job = loadJob(jobId);
  const desiredMode = classifyMode(taskDescription);
  if (job.mode !== desiredMode) {
    job.mode = desiredMode;
    job.channel = channelFor(jobId, desiredMode);
    appendHistory(job, {
      type: 'channel-updated',
      reason: 'task-classification',
      taskDescription,
      mode: desiredMode,
      channel: job.channel,
    });
    saveJob(job);
  }
  return job;
}

function addEvent(jobId, kind, message, actor) {
  const job = loadJob(jobId);
  appendHistory(job, { type: kind, actor: actor || null, message });
  saveJob(job);
  return job;
}

function closeJob(jobId, summary) {
  const job = loadJob(jobId);
  job.status = 'closed';
  job.summary = summary;
  appendHistory(job, { type: 'closed', summary });
  saveJob(job);
  return job;
}

function print(value) {
  if (typeof value === 'string') {
    process.stdout.write(value + '\n');
    return;
  }
  process.stdout.write(JSON.stringify(value, null, 2) + '\n');
}

function main(argv) {
  const [command, ...args] = argv;
  switch (command) {
    case 'create': {
      const [title, agent, mode] = args;
      if (!title) throw new Error('Usage: create <title> [agent] [mode]');
      print(createJob(title, agent, mode || runtimeConfig().jobs?.defaultMode || 'ops').jobId);
      return;
    }
    case 'channel': {
      const [jobId] = args;
      if (!jobId) throw new Error('Usage: channel <jobId>');
      print(loadJob(jobId).channel);
      return;
    }
    case 'show': {
      const [jobId] = args;
      if (!jobId) throw new Error('Usage: show <jobId>');
      print(loadJob(jobId));
      return;
    }
    case 'ensure-channel': {
      const [jobId, taskDescription] = args;
      if (!jobId) throw new Error('Usage: ensure-channel <jobId> <taskDescription>');
      print(ensureChannel(jobId, taskDescription || '').channel);
      return;
    }
    case 'event': {
      const [jobId, kind, message, actor] = args;
      if (!jobId || !kind) throw new Error('Usage: event <jobId> <kind> <message> [actor]');
      print(addEvent(jobId, kind, message || '', actor));
      return;
    }
    case 'close': {
      const [jobId, summary] = args;
      if (!jobId) throw new Error('Usage: close <jobId> <summary>');
      print(closeJob(jobId, summary || '')); 
      return;
    }
    default:
      throw new Error('Commands: create | channel | show | ensure-channel | event | close');
  }
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message || String(error));
  process.exit(1);
}
