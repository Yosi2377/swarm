// Task Decomposer — breaks large tasks into subtasks with dependency graphs

const { inferContract } = require('./task-contract');

// Patterns indicating multiple actions
const MULTI_PATTERNS = [
  /\d+\.\s+/g,                    // "1. ... 2. ... 3. ..."
  /\band\b/gi,                    // "X and Y"
  /\bו(?:גם|-)?\b/g,             // Hebrew "ו" / "וגם"
  /\bגם\b/g,                     // Hebrew "גם"
  /\bthen\b/gi,                   // "do X then Y"
  /\bאחר כך\b/g,                 // Hebrew "after that"
];

// Keywords suggesting complexity
const COMPLEX_KEYWORDS = [
  'architecture', 'redesign', 'migrate', 'refactor entire', 'rewrite',
  'ארכיטקטורה', 'שכתוב', 'מיגרציה', 'מערכת חדשה'
];

const MEDIUM_KEYWORDS = [
  'multiple files', 'several', 'כמה קבצים', 'מספר'
];

/**
 * Check if task needs decomposition.
 */
function shouldDecompose(taskDescription) {
  if (!taskDescription || taskDescription.length < 20) return false;

  // Check for numbered lists
  const numberedItems = taskDescription.match(/\d+\.\s+/g);
  if (numberedItems && numberedItems.length >= 2) return true;

  // Check for "and"/"ו" connecting different actions (heuristic: has verb-like words on both sides)
  const andSplits = taskDescription.split(/\band\b|\bוגם\b|\bגם\b/i).filter(s => s.trim().length > 10);
  if (andSplits.length < 2) {
    // Try splitting on Hebrew vav prefix (ו at word boundary)
    const vavSplits = taskDescription.split(/\s+ו(?=[א-ת])/).filter(s => s.trim().length > 10);
    if (vavSplits.length >= 2) return true;
  }
  if (andSplits.length >= 2) {
    // Verify they look like separate actions (contain different verbs/file refs)
    const uniqueWords = new Set();
    let distinct = 0;
    for (const part of andSplits) {
      const words = part.toLowerCase().trim().split(/\s+/).slice(0, 3).join(' ');
      if (!uniqueWords.has(words)) { uniqueWords.add(words); distinct++; }
    }
    if (distinct >= 2) return true;
  }

  // Check for multiple file types
  const fileExts = taskDescription.match(/\.\w{1,5}\b/g);
  if (fileExts) {
    const unique = new Set(fileExts.map(e => e.toLowerCase()));
    if (unique.size >= 3) return true;
  }

  // Complex keywords suggest decomposition
  for (const kw of COMPLEX_KEYWORDS) {
    if (taskDescription.toLowerCase().includes(kw)) return true;
  }

  return false;
}

/**
 * Break task into subtasks, each with its own mini-contract.
 */
function decompose(taskDescription, contract) {
  const subtasks = [];

  // Strategy 1: Numbered list
  const numberedRegex = /(?:^|\n)\s*(\d+)\.\s+(.+?)(?=(?:\n\s*\d+\.)|$)/gs;
  let match;
  const numbered = [];
  while ((match = numberedRegex.exec(taskDescription)) !== null) {
    numbered.push({ num: parseInt(match[1]), text: match[2].trim() });
  }

  if (numbered.length >= 2) {
    for (const item of numbered) {
      subtasks.push({
        id: `subtask-${item.num}`,
        description: item.text,
        contract: inferContract(item.text),
        dependsOn: item.num > 1 ? [`subtask-${item.num - 1}`] : [],
        order: item.num
      });
    }
    return subtasks;
  }

  // Strategy 2: Split by "and" / "ו" / "גם"
  const parts = taskDescription
    .split(/\b(?:and|then)\b|(?:ו(?:גם)?|גם|אחר כך)/i)
    .map(s => s.trim())
    .filter(s => s.length > 10);

  if (parts.length >= 2) {
    parts.forEach((part, i) => {
      subtasks.push({
        id: `subtask-${i + 1}`,
        description: part,
        contract: inferContract(part),
        dependsOn: [],
        order: i + 1
      });
    });
    return subtasks;
  }

  // Strategy 3: Sentence boundaries
  const sentences = taskDescription
    .split(/[.!?]\s+/)
    .map(s => s.trim())
    .filter(s => s.length > 15);

  if (sentences.length >= 3) {
    sentences.forEach((sent, i) => {
      subtasks.push({
        id: `subtask-${i + 1}`,
        description: sent,
        contract: inferContract(sent),
        dependsOn: [],
        order: i + 1
      });
    });
    return subtasks;
  }

  // Can't decompose — return single task
  return [{
    id: 'subtask-1',
    description: taskDescription,
    contract: contract || inferContract(taskDescription),
    dependsOn: [],
    order: 1
  }];
}

/**
 * Build dependency graph and execution plan.
 */
function buildDependencyGraph(subtasks) {
  const graph = {};
  const inDegree = {};

  for (const st of subtasks) {
    graph[st.id] = st.dependsOn || [];
    inDegree[st.id] = (st.dependsOn || []).length;
  }

  // Topological sort for execution waves
  const waves = [];
  const visited = new Set();

  while (visited.size < subtasks.length) {
    const wave = [];
    for (const st of subtasks) {
      if (visited.has(st.id)) continue;
      const deps = graph[st.id] || [];
      if (deps.every(d => visited.has(d))) {
        wave.push(st.id);
      }
    }
    if (wave.length === 0) break; // circular dependency guard
    wave.forEach(id => visited.add(id));
    waves.push(wave);
  }

  return {
    subtasks: subtasks.map(st => ({ id: st.id, description: st.description, dependsOn: st.dependsOn })),
    waves,
    parallelizable: waves.some(w => w.length > 1),
    totalWaves: waves.length
  };
}

module.exports = { shouldDecompose, decompose, buildDependencyGraph };
