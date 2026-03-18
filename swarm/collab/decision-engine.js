/**
 * @module DecisionEngine
 * Propose decisions, vote (for/against/abstain), overlap detection,
 * and decision lifecycle management.
 */

const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.COLLAB_DB || 'teamwork_collab';
const COLLECTION = 'agent_decisions';

/** Valid vote values */
const VALID_VOTES = ['for', 'against', 'abstain'];
/** Valid status transitions */
const STATUS_FLOW = {
  proposed: ['voting', 'decided', 'overruled'],
  voting: ['decided', 'overruled'],
  decided: ['overruled'],
  overruled: [],
};

class DecisionEngine {
  /**
   * @param {Object} [opts]
   * @param {MongoClient} [opts.client]
   * @param {string} [opts.uri]
   * @param {string} [opts.dbName]
   */
  constructor(opts = {}) {
    this._uri = opts.uri || MONGO_URI;
    this._dbName = opts.dbName || DB_NAME;
    this._client = opts.client || null;
    this._db = null;
    this._col = null;
  }

  async connect() {
    if (!this._client) {
      this._client = new MongoClient(this._uri);
      await this._client.connect();
    }
    this._db = this._client.db(this._dbName);
    this._col = this._db.collection(COLLECTION);
    await this._col.createIndex({ conversation_id: 1 });
    await this._col.createIndex({ topic: 1 });
    await this._col.createIndex({ status: 1 });
    return this;
  }

  async close() {
    if (this._client) await this._client.close();
  }

  /**
   * Propose a new decision.
   * Checks for overlap with existing decided/voting topics.
   * @param {string} agentId - proposing agent
   * @param {string} topic - decision topic
   * @param {string} proposal - the proposal text
   * @param {Object} [opts]
   * @param {string} [opts.conversation_id]
   * @returns {Promise<{ok: boolean, decision?: Object, overlap_warning?: string}>}
   */
  async proposeDecision(agentId, topic, proposal, opts = {}) {
    // Overlap detection: check if topic was already decided
    const overlap = await this._findOverlap(topic);
    const warning = overlap
      ? `Warning: topic "${overlap.topic}" was already ${overlap.status} on ${overlap.timestamp.toISOString()}. Consider if re-debating is needed.`
      : null;

    const doc = {
      conversation_id: opts.conversation_id || 'default',
      topic,
      decision: proposal,
      proposed_by: agentId,
      decided_by: [],
      votes: {},
      timestamp: new Date(),
      status: 'proposed',
    };

    const result = await this._col.insertOne(doc);
    doc._id = result.insertedId;

    const response = { ok: true, decision: doc };
    if (warning) response.overlap_warning = warning;
    return response;
  }

  /**
   * Cast a vote on a decision.
   * @param {string} agentId
   * @param {string|ObjectId} decisionId
   * @param {'for'|'against'|'abstain'} vote
   * @param {string} [reason]
   * @returns {Promise<{ok: boolean, decision?: Object, error?: string}>}
   */
  async vote(agentId, decisionId, vote, reason = '') {
    if (!VALID_VOTES.includes(vote)) {
      return { ok: false, error: `Invalid vote "${vote}". Must be: ${VALID_VOTES.join(', ')}` };
    }

    const id = typeof decisionId === 'string' ? new ObjectId(decisionId) : decisionId;
    const decision = await this._col.findOne({ _id: id });
    if (!decision) return { ok: false, error: 'Decision not found' };

    if (decision.status === 'decided' || decision.status === 'overruled') {
      return { ok: false, error: `Cannot vote on ${decision.status} decision` };
    }

    // Record vote
    const voteKey = `votes.${agentId}`;
    const update = {
      $set: {
        [voteKey]: { vote, reason, timestamp: new Date() },
        status: 'voting',
      },
    };

    await this._col.updateOne({ _id: id }, update);
    const updated = await this._col.findOne({ _id: id });
    return { ok: true, decision: updated };
  }

  /**
   * Resolve a decision (mark as decided or overruled).
   * @param {string|ObjectId} decisionId
   * @param {'decided'|'overruled'} newStatus
   * @param {string[]} [decidedBy] - agents who agreed
   * @returns {Promise<{ok: boolean, decision?: Object, error?: string}>}
   */
  async resolveDecision(decisionId, newStatus, decidedBy = []) {
    const id = typeof decisionId === 'string' ? new ObjectId(decisionId) : decisionId;
    const decision = await this._col.findOne({ _id: id });
    if (!decision) return { ok: false, error: 'Decision not found' };

    const allowed = STATUS_FLOW[decision.status];
    if (!allowed || !allowed.includes(newStatus)) {
      return { ok: false, error: `Cannot transition from "${decision.status}" to "${newStatus}"` };
    }

    await this._col.updateOne({ _id: id }, {
      $set: { status: newStatus, decided_by: decidedBy, resolved_at: new Date() },
    });
    const updated = await this._col.findOne({ _id: id });
    return { ok: true, decision: updated };
  }

  /**
   * Get all decisions for a conversation.
   * @param {string} conversationId
   * @returns {Promise<Object[]>}
   */
  async getDecisions(conversationId) {
    return this._col.find({ conversation_id: conversationId }).sort({ timestamp: -1 }).toArray();
  }

  /**
   * Get a tally of votes for a decision.
   * @param {string|ObjectId} decisionId
   * @returns {Promise<{for: number, against: number, abstain: number, total: number, voters: Object}>}
   */
  async getVoteTally(decisionId) {
    const id = typeof decisionId === 'string' ? new ObjectId(decisionId) : decisionId;
    const decision = await this._col.findOne({ _id: id });
    if (!decision) return null;

    const tally = { for: 0, against: 0, abstain: 0, total: 0, voters: {} };
    for (const [agent, v] of Object.entries(decision.votes || {})) {
      tally[v.vote]++;
      tally.total++;
      tally.voters[agent] = v.vote;
    }
    return tally;
  }

  /**
   * Check for overlap with existing decisions on similar topics.
   * @param {string} topic
   * @returns {Promise<Object|null>}
   */
  async _findOverlap(topic) {
    const words = topic.toLowerCase().split(/\s+/).filter(w => w.length > 3);
    if (words.length === 0) return null;

    // Check decided/voting topics for keyword overlap
    const existing = await this._col.find({
      status: { $in: ['decided', 'voting'] },
    }).toArray();

    for (const d of existing) {
      const dWords = d.topic.toLowerCase().split(/\s+/);
      const overlap = words.filter(w => dWords.includes(w));
      if (overlap.length >= Math.ceil(words.length * 0.5)) {
        return d;
      }
    }
    return null;
  }

  get collection() { return this._col; }
}

module.exports = DecisionEngine;
