// Progress Tracker — reads/writes agent progress reports

const fs = require('fs');
const path = require('path');

const PROGRESS_DIR = process.env.PROGRESS_DIR || '/tmp/agent-progress';

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function progressPath(agentId, threadId) {
  return path.join(PROGRESS_DIR, `${agentId}-${threadId}.json`);
}

/**
 * Record a progress report from an agent
 */
function reportProgress(agentId, threadId, message, step) {
  ensureDir(PROGRESS_DIR);
  const p = progressPath(agentId, threadId);
  let existing = null;
  try { existing = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
  
  const currentStep = step || ((existing?.step || 0) + 1);
  const entry = {
    agent: agentId,
    thread: threadId,
    message: String(message || ''),
    timestamp: new Date().toISOString(),
    step: currentStep,
    history: (existing?.history || []).concat([{
      message: String(message || ''),
      timestamp: new Date().toISOString(),
      step: currentStep
    }])
  };
  
  // Keep last 20 history entries
  if (entry.history.length > 20) {
    entry.history = entry.history.slice(-20);
  }
  
  fs.writeFileSync(p, JSON.stringify(entry, null, 2));
  return entry;
}

/**
 * Get latest progress for an agent task
 */
function getProgress(agentId, threadId) {
  const p = progressPath(agentId, threadId);
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

/**
 * Get all progress reports
 */
function getAllProgress() {
  ensureDir(PROGRESS_DIR);
  const files = fs.readdirSync(PROGRESS_DIR).filter(f => f.endsWith('.json'));
  return files.map(f => {
    try { return JSON.parse(fs.readFileSync(path.join(PROGRESS_DIR, f), 'utf8')); }
    catch { return null; }
  }).filter(Boolean);
}

/**
 * Check if agent has recent progress (within minutesThreshold)
 */
function hasRecentProgress(agentId, threadId, minutesThreshold) {
  const threshold = minutesThreshold || 3;
  const progress = getProgress(agentId, threadId);
  if (!progress || !progress.timestamp) return false;
  const elapsed = (Date.now() - new Date(progress.timestamp).getTime()) / 60000;
  return elapsed < threshold;
}

/**
 * Get progress summary for retry context
 */
function getProgressSummary(agentId, threadId) {
  const progress = getProgress(agentId, threadId);
  if (!progress || !progress.history || progress.history.length === 0) {
    return 'No progress reports were made.';
  }
  return progress.history.map(h => `Step ${h.step}: ${h.message}`).join('\n');
}

module.exports = {
  PROGRESS_DIR,
  reportProgress,
  getProgress,
  getAllProgress,
  hasRecentProgress,
  getProgressSummary,
};
