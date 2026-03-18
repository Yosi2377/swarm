/**
 * @module ReputationTracker
 * Score tracking per agent, delta history, decay over time.
 * Higher reputation = suggestions weighted more in votes.
 */

const { MongoClient } = require('mongodb');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.COLLAB_DB || 'teamwork_collab';
const COLLECTION = 'agent_reputation';

const INITIAL_SCORE = 100;
const DECAY_RATE = 0.01; // 1% decay per day of inactivity
const DECAY_GRACE_DAYS = 3; // no decay for 3 days

/** Score deltas per event type */
const EVENT_DELTAS = {
  task_completed: 10,
  good_review: 5,
  bad_suggestion: -3,
  vote_cast: 2,
  decision_made: 3,
  review_submitted: 4,
  review_approved: 3,
  review_rejected: -2,
  escalation_caused: -5,
  helpful_feedback: 5,
  bug_found: 8,
  kb_contribution: 2,
};

class ReputationTracker {
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
    await this._col.createIndex({ agent_id: 1 }, { unique: true });
    return this;
  }

  async close() {
    if (this._client) await this._client.close();
  }

  /**
   * Get or initialize reputation for an agent.
   * @param {string} agentId
   * @returns {Promise<Object>}
   */
  async getReputation(agentId) {
    let rep = await this._col.findOne({ agent_id: agentId });
    if (!rep) {
      rep = {
        agent_id: agentId,
        score: INITIAL_SCORE,
        history: [],
        first_seen: new Date(),
        last_active: new Date(),
      };
      await this._col.insertOne(rep);
    }
    return rep;
  }

  /**
   * Record an event and update score.
   * @param {string} agentId
   * @param {string} event - event type (from EVENT_DELTAS keys, or custom)
   * @param {number} [customDelta] - override delta (optional)
   * @returns {Promise<{ok: boolean, score: number, delta: number}>}
   */
  async recordEvent(agentId, event, customDelta) {
    const delta = customDelta !== undefined ? customDelta : (EVENT_DELTAS[event] || 0);
    const entry = { event, delta, timestamp: new Date() };

    // Ensure agent exists with initial score first
    await this._col.updateOne(
      { agent_id: agentId },
      {
        $setOnInsert: { agent_id: agentId, score: INITIAL_SCORE, history: [], first_seen: new Date() },
      },
      { upsert: true }
    );
    // Then apply delta
    await this._col.updateOne(
      { agent_id: agentId },
      {
        $inc: { score: delta },
        $push: { history: { $each: [entry], $slice: -100 } },
        $set: { last_active: new Date() },
      }
    );

    const updated = await this._col.findOne({ agent_id: agentId });
    return { ok: true, score: updated.score, delta };
  }

  /**
   * Apply decay to inactive agents.
   * Reduces score by DECAY_RATE per day after DECAY_GRACE_DAYS of inactivity.
   * @returns {Promise<{decayed: string[]}>}
   */
  async applyDecay() {
    const now = new Date();
    const graceMs = DECAY_GRACE_DAYS * 86400000;
    const agents = await this._col.find({}).toArray();
    const decayed = [];

    for (const agent of agents) {
      const inactiveMs = now - new Date(agent.last_active);
      if (inactiveMs > graceMs) {
        const daysInactive = (inactiveMs - graceMs) / 86400000;
        const decayAmount = Math.floor(agent.score * DECAY_RATE * daysInactive);
        if (decayAmount > 0) {
          await this._col.updateOne(
            { agent_id: agent.agent_id },
            {
              $inc: { score: -decayAmount },
              $push: {
                history: {
                  $each: [{ event: 'decay', delta: -decayAmount, timestamp: now }],
                  $slice: -100,
                },
              },
            }
          );
          decayed.push(agent.agent_id);
        }
      }
    }

    return { decayed };
  }

  /**
   * Get leaderboard of all agents sorted by score.
   * @returns {Promise<Object[]>}
   */
  async getLeaderboard() {
    return this._col.find({}).sort({ score: -1 }).toArray();
  }

  get collection() { return this._col; }
}

module.exports = ReputationTracker;
