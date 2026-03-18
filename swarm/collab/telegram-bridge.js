/**
 * @module TelegramBridge
 * Posts conversation highlights (decisions, disagreements, resolutions)
 * to Telegram topics via send.sh. Avoids spam — only key events.
 */

const { execSync } = require('child_process');
const path = require('path');

const SEND_SH = path.resolve(__dirname, '..', 'send.sh');

class TelegramBridge {
  /**
   * @param {Object} [opts]
   * @param {string} [opts.sendScript] - path to send.sh
   * @param {string} [opts.defaultAgent] - default agent identity for posts
   * @param {number} [opts.defaultTopic] - default Telegram topic ID
   */
  constructor(opts = {}) {
    this._sendScript = opts.sendScript || SEND_SH;
    this._defaultAgent = opts.defaultAgent || 'koder';
    this._defaultTopic = opts.defaultTopic || null;
    this._lastPostAt = 0;
    this._minInterval = 5000; // min 5s between posts
  }

  /**
   * Post a message to a Telegram topic via send.sh.
   * @param {string} agentId - agent identity for the bot
   * @param {number} topicId - Telegram topic/thread ID
   * @param {string} message - message text
   * @returns {{ok: boolean, error?: string}}
   */
  post(agentId, topicId, message) {
    try {
      const escaped = message.replace(/'/g, "'\\''");
      const prefix = this._sendScript.endsWith('.sh') ? 'bash ' : '';
      execSync(`${prefix}'${this._sendScript}' '${agentId}' '${topicId}' '${escaped}'`, {
        timeout: 10000,
        stdio: 'pipe',
      });
      this._lastPostAt = Date.now();
      return { ok: true };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }

  /**
   * Post a decision highlight.
   * @param {Object} decision - decision object from DecisionEngine
   * @param {number} topicId
   */
  postDecision(decision, topicId) {
    const emoji = decision.status === 'decided' ? '✅' : decision.status === 'overruled' ? '🚫' : '🗳️';
    const votes = decision.votes || {};
    const voteSummary = Object.entries(votes)
      .map(([agent, v]) => `${agent}: ${v.vote || v}`)
      .join(', ');
    const msg = `${emoji} Decision: ${decision.topic}\n` +
      `Status: ${decision.status}\n` +
      `Proposal: ${decision.decision}\n` +
      (voteSummary ? `Votes: ${voteSummary}` : '');
    return this.post(this._defaultAgent, topicId, msg);
  }

  /**
   * Post a disagreement alert.
   * @param {Object} review - review object from ReviewSystem
   * @param {number} topicId
   */
  postDisagreement(review, topicId) {
    const reviewers = (review.reviews || []).map(r => `${r.reviewer}: ${r.verdict}`).join(', ');
    const msg = `⚠️ Disagreement on review\n` +
      `Requested by: ${review.requested_by}\n` +
      `Context: ${review.context}\n` +
      `Reviews: ${reviewers}\n` +
      `Status: ESCALATED`;
    return this.post(this._defaultAgent, topicId, msg);
  }

  /**
   * Post a resolution summary.
   * @param {string} topic
   * @param {string} resolution
   * @param {number} topicId
   */
  postResolution(topic, resolution, topicId) {
    const msg = `🎯 Resolved: ${topic}\nOutcome: ${resolution}`;
    return this.post(this._defaultAgent, topicId, msg);
  }

  /**
   * Post a conversation summary.
   * @param {Object} summary
   * @param {number} topicId
   */
  postSummary(summary, topicId) {
    const msg = `📊 Collaboration Summary\n` +
      `Messages: ${summary.messageCount || 0}\n` +
      `Decisions: ${summary.decisionCount || 0}\n` +
      `Reviews: ${summary.reviewCount || 0}\n` +
      (summary.highlights ? `\nHighlights:\n${summary.highlights}` : '');
    return this.post(this._defaultAgent, topicId, msg);
  }
}

module.exports = TelegramBridge;
