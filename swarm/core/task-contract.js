// Task Contract — main contract logic for the agent swarm

const crypto = require('crypto');
const { TASK_TYPES, getTemplate } = require('./contract-templates');
const { validateContract } = require('./contract-validator');

function generateId() {
  return `tc-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
}

/**
 * Create a new task contract with template defaults.
 */
function createContract(type, description) {
  if (!TASK_TYPES.includes(type)) {
    throw new Error(`Unknown task type: "${type}". Must be one of: ${TASK_TYPES.join(', ')}`);
  }
  const tpl = getTemplate(type);
  return {
    id: generateId(),
    type,
    input: { description, context: '', constraints: [] },
    expected_artifacts: tpl.expected_artifacts,
    acceptance_criteria: tpl.acceptance_criteria,
    rollback: tpl.rollback,
    metadata: { ...tpl.metadata, depends_on: [], blocks: [] }
  };
}

// Keyword map for Hebrew + English inference
const INFER_MAP = [
  { type: 'security_fix', keywords: ['אבטחה', 'vulnerability', 'security', 'xss', 'csrf', 'injection', 'סריקה', 'חדירה'] },
  { type: 'db_migration', keywords: ['migration', 'מיגרציה', 'schema', 'סכמה', 'database', 'דאטאבייס', 'טבלה', 'collection'] },
  { type: 'ui_change', keywords: ['ui', 'עיצוב', 'כפתור', 'button', 'css', 'style', 'layout', 'responsive', 'תצוגה', 'דף'] },
  { type: 'api_endpoint', keywords: ['api', 'endpoint', 'route', 'rest', 'graphql', 'נתיב'] },
  { type: 'config_change', keywords: ['config', 'הגדרות', 'env', 'environment', 'קונפיג', '.env', 'settings'] },
  { type: 'refactor', keywords: ['refactor', 'ריפקטור', 'clean', 'ניקוי', 'optimize', 'שיפור קוד'] },
  { type: 'research', keywords: ['research', 'מחקר', 'investigate', 'חקירה', 'בדיקה', 'compare', 'השוואה'] },
  { type: 'feature', keywords: ['feature', 'פיצ\'ר', 'add', 'הוסף', 'חדש', 'new', 'implement', 'מימוש'] },
  { type: 'code_fix', keywords: ['fix', 'bug', 'תקן', 'תתקן', 'באג', 'שגיאה', 'error', 'broken', 'שבור', 'לא עובד', 'crash'] },
];

/**
 * Infer contract type from free-text task description (Hebrew/English).
 */
function inferContract(taskDescription) {
  const lower = taskDescription.toLowerCase();
  for (const { type, keywords } of INFER_MAP) {
    for (const kw of keywords) {
      if (lower.includes(kw)) {
        return createContract(type, taskDescription);
      }
    }
  }
  // Default to code_fix
  return createContract('code_fix', taskDescription);
}

/**
 * Extract concrete verifiable items from task description.
 * Finds URLs, file paths, CSS selectors, text strings, etc.
 */
function extractVerifiables(description) {
  const verifiables = { urls: [], files: [], selectors: [], texts: [], patterns: [] };
  
  // URLs
  const urlRegex = /https?:\/\/[^\s"'<>]+/g;
  verifiables.urls = (description.match(urlRegex) || []);
  
  // File paths
  const pathRegex = /\/[\w\-.\/]+\.\w+/g;
  verifiables.files = (description.match(pathRegex) || []);
  
  // CSS selectors (#id, .class)
  const selectorRegex = /[#.]\w[\w-]+/g;
  const potentialSelectors = (description.match(selectorRegex) || []).filter(s => 
    !s.startsWith('.js') && !s.startsWith('.html') && !s.startsWith('.css') && !s.startsWith('.md')
  );
  verifiables.selectors = potentialSelectors;
  
  // Quoted strings (things user expects to see)
  const quotedRegex = /["'`]([^"'`]{2,50})["'`]/g;
  let m;
  while ((m = quotedRegex.exec(description))) {
    verifiables.texts.push(m[1]);
  }
  
  // Key terms after "הוסף"/"add"/"צריך להיות"/"should contain"
  const addRegex = /(?:הוסף|add|צריך להיות|should (?:contain|show|have|display))\s+(.{3,40})/gi;
  while ((m = addRegex.exec(description))) {
    verifiables.patterns.push(m[1].trim());
  }
  
  return verifiables;
}

/**
 * Enrich a contract with project-specific config AND concrete criteria.
 */
function enrichContract(contract, projectConfig = {}) {
  const enriched = JSON.parse(JSON.stringify(contract));
  
  // Basic project info
  const pc = projectConfig;
  if (pc.basePath || pc.path) {
    enriched.input.context = `Project: ${pc.basePath || pc.path}`;
  }
  if (pc.name) enriched.input.context += ` (${pc.name})`;
  
  // Store project config for verify
  enriched._projectConfig = {
    path: pc.path || pc.basePath || '',
    sandbox: pc.sandbox || '',
    url: pc.url || '',
    sandboxUrl: pc.sandboxUrl || '',
    testCommand: pc.testCommand || '',
    service: pc.service || '',
    sandboxService: pc.sandboxService || '',
    db: pc.db || ''
  };
  
  // Add test command criterion
  if (pc.testCommand) {
    enriched.acceptance_criteria.push({
      type: 'test_passes',
      command: pc.testCommand,
      cwd: pc.sandbox || pc.path || '.',
      description: `Project tests pass: ${pc.testCommand}`
    });
  }
  
  // Add HTTP check for sandbox URL
  if (pc.sandboxUrl) {
    enriched.acceptance_criteria.push({
      type: 'http_status',
      url: pc.sandboxUrl,
      expected: 200,
      description: `Sandbox responds: ${pc.sandboxUrl}`
    });
  }
  
  // Add service health check
  if (pc.sandboxService) {
    enriched.acceptance_criteria.push({
      type: 'custom',
      script: `systemctl is-active ${pc.sandboxService}`,
      description: `Service running: ${pc.sandboxService}`
    });
  }
  
  // Extract concrete verifiables from task description
  const v = extractVerifiables(enriched.input.description);
  
  // Add URL-specific checks
  for (const url of v.urls) {
    if (!enriched.acceptance_criteria.some(c => c.url === url)) {
      // If it's a link that should appear in the page, check for it
      enriched.acceptance_criteria.push({
        type: 'file_contains',
        file: '*', // will be resolved to sandbox files
        pattern: url.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
        description: `URL appears in code: ${url}`
      });
    }
  }
  
  // Add text pattern checks
  for (const text of v.texts) {
    enriched.acceptance_criteria.push({
      type: 'file_contains',
      file: '*',
      pattern: text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
      description: `Text appears: "${text}"`
    });
  }
  
  // Add pattern checks
  for (const pattern of v.patterns) {
    enriched.acceptance_criteria.push({
      type: 'file_contains',
      file: '*',
      pattern: pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
      description: `Pattern appears: "${pattern}"`
    });
  }
  
  // Priority override
  if (pc.priority) enriched.metadata.priority = pc.priority;
  
  // Resolve file_contains with '*' to actual sandbox path
  const sandboxPublic = (pc.sandbox || pc.path || '') + '/public/index.html';
  enriched.acceptance_criteria = enriched.acceptance_criteria.map(c => {
    if (c.type === 'file_contains' && c.file === '*') {
      return { ...c, file: sandboxPublic };
    }
    return c;
  });
  
  return enriched;
}

module.exports = {
  TASK_TYPES,
  createContract,
  inferContract,
  validateContract,
  enrichContract
};
