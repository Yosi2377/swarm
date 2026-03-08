// Contract Templates — sensible defaults per task type

const TASK_TYPES = [
  'code_fix', 'feature', 'ui_change', 'api_endpoint',
  'db_migration', 'security_fix', 'refactor', 'research', 'config_change'
];

const templates = {
  code_fix: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'test_pass', description: 'Relevant tests pass' },
      { type: 'no_regression', description: 'No new test failures' },
      { type: 'manual_verify', description: 'Bug no longer reproducible' },
      { type: 'screenshot_sent', description: 'Before/after screenshots sent to Telegram topic' }
    ],
    rollback: { strategy: 'git_revert', auto: false },
    metadata: { priority: 'high', estimated_minutes: 30, depends_on: [], blocks: [] }
  },
  feature: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'test_pass', description: 'New feature tests pass' },
      { type: 'no_regression', description: 'Existing tests unbroken' },
      { type: 'docs_updated', description: 'Documentation updated if needed' },
      { type: 'screenshot_sent', description: 'Screenshots of new feature sent to Telegram topic' }
    ],
    rollback: { strategy: 'git_revert', auto: false },
    metadata: { priority: 'medium', estimated_minutes: 120, depends_on: [], blocks: [] }
  },
  ui_change: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'visual_check', description: 'UI renders correctly' },
      { type: 'responsive', description: 'Works on mobile and desktop' },
      { type: 'no_regression', description: 'No visual regressions' },
      { type: 'screenshot_sent', description: 'Before/after screenshots sent to Telegram topic (desktop 1280px + mobile 375px)' }
    ],
    rollback: { strategy: 'git_revert', auto: false },
    metadata: { priority: 'medium', estimated_minutes: 60, depends_on: [], blocks: [] }
  },
  api_endpoint: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'test_pass', description: 'Endpoint tests pass' },
      { type: 'schema_valid', description: 'Request/response schema validated' },
      { type: 'auth_check', description: 'Authentication/authorization verified' }
    ],
    rollback: { strategy: 'git_revert', auto: false },
    metadata: { priority: 'high', estimated_minutes: 90, depends_on: [], blocks: [] }
  },
  db_migration: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'migration_up', description: 'Migration applies cleanly' },
      { type: 'migration_down', description: 'Rollback migration works' },
      { type: 'data_integrity', description: 'No data loss' }
    ],
    rollback: { strategy: 'migration_down', auto: false },
    metadata: { priority: 'critical', estimated_minutes: 60, depends_on: [], blocks: [] }
  },
  security_fix: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'vulnerability_fixed', description: 'Vulnerability no longer exploitable' },
      { type: 'test_pass', description: 'Security tests pass' },
      { type: 'no_regression', description: 'No functionality broken' }
    ],
    rollback: { strategy: 'git_revert', auto: false },
    metadata: { priority: 'critical', estimated_minutes: 45, depends_on: [], blocks: [] }
  },
  refactor: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'test_pass', description: 'All existing tests pass' },
      { type: 'no_regression', description: 'Behavior unchanged' },
      { type: 'code_quality', description: 'Code quality improved (measurable)' }
    ],
    rollback: { strategy: 'git_revert', auto: false },
    metadata: { priority: 'low', estimated_minutes: 90, depends_on: [], blocks: [] }
  },
  research: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'report_complete', description: 'Research document produced' },
      { type: 'actionable', description: 'Clear recommendations provided' }
    ],
    rollback: { strategy: 'none', auto: false },
    metadata: { priority: 'medium', estimated_minutes: 120, depends_on: [], blocks: [] }
  },
  config_change: {
    expected_artifacts: { files_changed: [], endpoints_affected: [], ui_elements: [] },
    acceptance_criteria: [
      { type: 'config_valid', description: 'Configuration parses correctly' },
      { type: 'service_healthy', description: 'Service starts with new config' },
      { type: 'no_regression', description: 'No functionality broken' }
    ],
    rollback: { strategy: 'git_revert', auto: true },
    metadata: { priority: 'medium', estimated_minutes: 15, depends_on: [], blocks: [] }
  }
};

function getTemplate(type) {
  if (!templates[type]) throw new Error(`Unknown task type: ${type}`);
  return JSON.parse(JSON.stringify(templates[type]));
}

function getAllTemplates() {
  return { ...templates };
}

module.exports = { TASK_TYPES, templates, getTemplate, getAllTemplates };
