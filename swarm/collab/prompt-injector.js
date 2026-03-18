/**
 * @module PromptInjector
 * Generate collaboration instructions for agent prompts based on task type.
 * Reads templates and customizes them for the specific collaboration context.
 */

const fs = require('fs');
const path = require('path');

const TEMPLATES_DIR = path.join(__dirname, 'templates');

class PromptInjector {
  /**
   * @param {Object} [opts]
   * @param {string} [opts.templatesDir] - path to templates directory
   */
  constructor(opts = {}) {
    this._templatesDir = opts.templatesDir || TEMPLATES_DIR;
  }

  /**
   * Load a template file.
   * @param {string} name - template name (without .md)
   * @returns {string}
   */
  _loadTemplate(name) {
    const filePath = path.join(this._templatesDir, `${name}.md`);
    if (!fs.existsSync(filePath)) {
      return `[Template "${name}" not found]`;
    }
    return fs.readFileSync(filePath, 'utf8');
  }

  /**
   * Generate collaboration prompt for a task.
   * @param {'collab'|'debate'|'review'} taskType
   * @param {Object} context
   * @param {string} context.agentId - this agent's ID
   * @param {string[]} [context.participants] - other agents in the collab
   * @param {string} [context.topic] - topic of collaboration
   * @param {string} [context.conversationId]
   * @param {Object} [context.reputation] - agent's reputation data
   * @returns {string} prompt text to inject
   */
  generate(taskType, context = {}) {
    const templateMap = {
      collab: 'collab-prompt',
      debate: 'debate-prompt',
      review: 'review-prompt',
    };

    const templateName = templateMap[taskType] || 'collab-prompt';
    let template = this._loadTemplate(templateName);

    // Variable substitution
    const vars = {
      '{{AGENT_ID}}': context.agentId || 'unknown',
      '{{PARTICIPANTS}}': (context.participants || []).join(', ') || 'none',
      '{{TOPIC}}': context.topic || 'general',
      '{{CONVERSATION_ID}}': context.conversationId || 'default',
      '{{REP_SCORE}}': context.reputation ? String(context.reputation.score) : '100',
    };

    for (const [key, val] of Object.entries(vars)) {
      template = template.replace(new RegExp(key.replace(/[{}]/g, '\\$&'), 'g'), val);
    }

    return template;
  }

  /**
   * Generate a minimal instruction set (for constrained prompt space).
   * @param {string} agentId
   * @param {'collab'|'debate'|'review'} taskType
   * @returns {string}
   */
  generateMinimal(agentId, taskType) {
    const rules = [
      `You are ${agentId}. You are collaborating with other agents.`,
      'LISTEN before speaking — always check what others said first.',
      'Only respond when you have NEW information to add.',
      'Disagree constructively — state what, why, and propose alternative.',
      'Check existing decisions before re-debating settled topics.',
      'Budget: max 2 unsolicited messages per minute.',
    ];

    if (taskType === 'debate') {
      rules.push('State your position clearly with reasoning.');
      rules.push('Vote honestly — don\'t just agree with majority.');
    }

    if (taskType === 'review') {
      rules.push('Review code carefully — approve, reject, or request changes.');
      rules.push('If you disagree with another reviewer, explain why explicitly.');
    }

    return rules.join('\n');
  }
}

module.exports = PromptInjector;
