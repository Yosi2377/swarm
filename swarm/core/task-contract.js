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
 * Enrich a contract with project-specific config.
 */
function enrichContract(contract, projectConfig = {}) {
  const enriched = JSON.parse(JSON.stringify(contract));
  if (projectConfig.basePath) {
    enriched.input.context = `Project: ${projectConfig.basePath}`;
  }
  if (projectConfig.testCommand) {
    enriched.acceptance_criteria.push({
      type: 'test_pass',
      description: `Run: ${projectConfig.testCommand}`
    });
  }
  if (projectConfig.priority) {
    enriched.metadata.priority = projectConfig.priority;
  }
  return enriched;
}

module.exports = {
  TASK_TYPES,
  createContract,
  inferContract,
  validateContract,
  enrichContract
};
