/**
 * @module ConversationManager
 * Core messaging system with adaptive cooldown, response budget, 
 * should_respond logic, send-after-listen enforcement, and smart context.
 * 
 * Inspired by let-them-talk's agent-bridge cooldown math and priority batching.
 */

const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.COLLAB_DB || 'teamwork_collab';
const COLLECTION = 'agent_conversations';

// Budget & cooldown constants
const BUDGET_WINDOW_MS = 60000;        // 60s window for response budget
const MAX_UNADDRESSED_PER_WINDOW = 2;  // max 2 unsolicited msgs per window
const BASE_COOLDOWN_MS = 500;          // fast lane (addressed replies)
const SLOW_LANE_MULTIPLIER = 2;        // slow lane = max(2000, members * 1000)
const MIN_SLOW_COOLDOWN_MS = 2000;

/**
 * @typedef {Object} AgentState
 * @property {number} lastSentAt - timestamp of last send
 * @property {number} sendsSinceLastListen - must listen between sends
 * @property {number} sendLimit - 1 normally, 2 if addressed
 * @property {number} unaddressedSends - count in current budget window
 * @property {number} budgetResetTime - when current budget window started
 * @property {number} lastListenAt - when agent last called listen
 */

class ConversationManager {
  /**
   * @param {Object} [opts]
   * @param {MongoClient} [opts.client] - existing MongoClient
   * @param {string} [opts.uri] - MongoDB URI
   * @param {string} [opts.dbName] - database name
   */
  constructor(opts = {}) {
    this._uri = opts.uri || MONGO_URI;
    this._dbName = opts.dbName || DB_NAME;
    this._client = opts.client || null;
    this._db = null;
    this._col = null;
    /** @type {Map<string, AgentState>} */
    this._agents = new Map();
  }

  /** Connect to MongoDB */
  async connect() {
    if (!this._client) {
      this._client = new MongoClient(this._uri);
      await this._client.connect();
    }
    this._db = this._client.db(this._dbName);
    this._col = this._db.collection(COLLECTION);
    await this._col.createIndex({ conversation_id: 1, timestamp: 1 });
    await this._col.createIndex({ 'addressed_to': 1 });
    await this._col.createIndex({ channel: 1 });
    return this;
  }

  /** Close connection */
  async close() {
    if (this._client) await this._client.close();
  }

  /** Get or init agent state */
  _state(agentId) {
    if (!this._agents.has(agentId)) {
      this._agents.set(agentId, {
        lastSentAt: 0,
        sendsSinceLastListen: 0,
        sendLimit: 1,
        unaddressedSends: 0,
        budgetResetTime: Date.now(),
        lastListenAt: 0,
      });
    }
    return this._agents.get(agentId);
  }

  /**
   * Compute adaptive cooldown based on channel member count and addressing.
   * Fast lane (reply/addressed): 500ms
   * Slow lane (unaddressed): max(2000, memberCount * 1000)
   * @param {number} memberCount
   * @param {boolean} isAddressed
   * @returns {number} cooldown in ms
   */
  getAdaptiveCooldown(memberCount, isAddressed) {
    if (isAddressed) return BASE_COOLDOWN_MS;
    return Math.max(MIN_SLOW_COOLDOWN_MS, memberCount * 1000);
  }

  /**
   * Check and enforce response budget for unaddressed messages.
   * @param {string} agentId
   * @returns {{allowed: boolean, remaining: number, resetIn: number}}
   */
  checkBudget(agentId) {
    const s = this._state(agentId);
    const now = Date.now();
    if (now - s.budgetResetTime > BUDGET_WINDOW_MS) {
      s.unaddressedSends = 0;
      s.budgetResetTime = now;
    }
    const remaining = MAX_UNADDRESSED_PER_WINDOW - s.unaddressedSends;
    return {
      allowed: remaining > 0,
      remaining: Math.max(0, remaining),
      resetIn: BUDGET_WINDOW_MS - (now - s.budgetResetTime),
    };
  }

  /**
   * Send a message with cooldown, budget, and send-after-listen enforcement.
   * @param {string} from - sender agent ID
   * @param {string} to - recipient agent ID or '__group__'
   * @param {string} content - message text
   * @param {Object} [opts]
   * @param {string} [opts.conversation_id]
   * @param {string[]} [opts.addressed_to] - who should respond
   * @param {string} [opts.reply_to] - message ID for threading
   * @param {string} [opts.thread_id]
   * @param {string} [opts.channel] - 'general', 'code-review', etc.
   * @param {string} [opts.type] - 'message', 'vote', 'decision', 'review'
   * @param {Object} [opts.metadata]
   * @returns {Promise<{ok: boolean, message?: Object, error?: string, cooldown_applied_ms?: number, budget_hint?: string}>}
   */
  async sendMessage(from, to, content, opts = {}) {
    const s = this._state(from);
    const isAddressed = !!(opts.reply_to || (opts.addressed_to && opts.addressed_to.length > 0));

    // Send-after-listen enforcement
    if (s.sendsSinceLastListen >= s.sendLimit) {
      return { ok: false, error: 'Must listen before sending again. Call listenForMessages() first.' };
    }

    // Budget check for unaddressed messages
    if (!isAddressed) {
      const budget = this.checkBudget(from);
      if (!budget.allowed) {
        return {
          ok: false,
          error: `Response budget depleted (${MAX_UNADDRESSED_PER_WINDOW} unaddressed/min). Wait ${Math.ceil(budget.resetIn / 1000)}s or be addressed.`,
        };
      }
    }

    // Adaptive cooldown
    const memberCount = this._agents.size || 2;
    const cooldown = this.getAdaptiveCooldown(memberCount, isAddressed);
    const elapsed = Date.now() - s.lastSentAt;
    let cooldownApplied = 0;
    if (elapsed < cooldown) {
      const waitMs = cooldown - elapsed;
      cooldownApplied = waitMs;
      await new Promise(r => setTimeout(r, waitMs));
    }

    const msg = {
      conversation_id: opts.conversation_id || 'default',
      from,
      to,
      content,
      timestamp: new Date(),
      addressed_to: opts.addressed_to || [],
      reply_to: opts.reply_to || null,
      thread_id: opts.thread_id || null,
      channel: opts.channel || 'general',
      type: opts.type || 'message',
      metadata: opts.metadata || {},
    };

    const result = await this._col.insertOne(msg);
    msg._id = result.insertedId;

    // Update state
    s.lastSentAt = Date.now();
    s.sendsSinceLastListen++;
    if (!isAddressed) s.unaddressedSends++;

    const response = { ok: true, message: msg };
    if (cooldownApplied > 0) response.cooldown_applied_ms = cooldownApplied;
    if (!isAddressed && s.unaddressedSends >= MAX_UNADDRESSED_PER_WINDOW) {
      response.budget_hint = 'Response budget depleted (2 unaddressed sends in 60s). Wait to be addressed or wait for budget reset.';
    }
    return response;
  }

  /**
   * Listen for messages targeting this agent. Resets send-after-listen counter.
   * Returns batch with should_respond hints and priority sorting.
   * @param {string} agentId
   * @param {Object} [opts]
   * @param {string} [opts.conversation_id]
   * @param {string} [opts.channel]
   * @param {number} [opts.since] - timestamp ms, only messages after this
   * @returns {Promise<{messages: Object[], should_respond: boolean, batch_summary: string}>}
   */
  async listenForMessages(agentId, opts = {}) {
    const s = this._state(agentId);
    s.sendsSinceLastListen = 0;
    s.lastListenAt = Date.now();

    const query = {};
    if (opts.conversation_id) query.conversation_id = opts.conversation_id;
    if (opts.channel) query.channel = opts.channel;
    if (opts.since) query.timestamp = { $gt: new Date(opts.since) };

    // Get messages where agent is recipient or in group
    query.$or = [
      { to: agentId },
      { to: '__group__' },
      { addressed_to: agentId },
    ];

    const messages = await this._col.find(query).sort({ timestamp: -1 }).limit(50).toArray();
    messages.reverse();

    // Priority sort: system > threaded > direct > broadcast
    const priorityOf = (m) => {
      if (m.type === 'system') return 0;
      if (m.reply_to || m.thread_id) return 1;
      if (m.to !== '__group__') return 2;
      return 3;
    };
    messages.sort((a, b) => {
      const pa = priorityOf(a), pb = priorityOf(b);
      if (pa !== pb) return pa - pb;
      return a.timestamp - b.timestamp;
    });

    // Annotate should_respond
    const wasAddressed = messages.some(m =>
      m.addressed_to && m.addressed_to.includes(agentId)
    );
    s.sendLimit = wasAddressed ? 2 : 1;

    const annotated = messages.map(m => ({
      ...m,
      should_respond: !m.addressed_to || m.addressed_to.length === 0 || m.addressed_to.includes(agentId),
      addressed_to_you: !!(m.addressed_to && m.addressed_to.includes(agentId)),
    }));

    // Batch summary
    const counts = {};
    for (const m of annotated) {
      const t = m.type || 'message';
      counts[t] = (counts[t] || 0) + 1;
    }
    const summaryParts = Object.entries(counts).map(([t, c]) => `${c} ${t}`);

    return {
      messages: annotated,
      should_respond: wasAddressed || annotated.some(m => m.to === agentId),
      batch_summary: `${annotated.length} messages: ${summaryParts.join(', ')}`,
    };
  }

  /**
   * Smart context: addressed > channel > recent.
   * Returns prioritized context messages for an agent.
   * @param {string} agentId
   * @param {Object} [opts]
   * @param {string} [opts.conversation_id]
   * @param {string[]} [opts.channels]
   * @param {number} [opts.maxSize] - total context messages (default 50)
   * @returns {Promise<{addressed: Object[], channel: Object[], recent: Object[]}>}
   */
  async getContext(agentId, opts = {}) {
    const maxSize = opts.maxSize || 50;
    const convFilter = opts.conversation_id ? { conversation_id: opts.conversation_id } : {};
    const seen = new Set();

    // Bucket A: addressed to me (up to 10)
    const addressed = await this._col.find({
      ...convFilter,
      addressed_to: agentId,
    }).sort({ timestamp: -1 }).limit(10).toArray();
    addressed.reverse();
    addressed.forEach(m => seen.add(m._id.toString()));

    // Bucket B: from my channels (up to 15)
    const channels = opts.channels || ['general'];
    const maxB = Math.min(15, maxSize - addressed.length);
    let channelMsgs = [];
    if (maxB > 0) {
      channelMsgs = await this._col.find({
        ...convFilter,
        channel: { $in: channels },
        _id: { $nin: addressed.map(m => m._id) },
      }).sort({ timestamp: -1 }).limit(maxB).toArray();
      channelMsgs.reverse();
      channelMsgs.forEach(m => seen.add(m._id.toString()));
    }

    // Bucket C: recent (fill remainder)
    const remaining = maxSize - addressed.length - channelMsgs.length;
    let recent = [];
    if (remaining > 0) {
      const excludeIds = [...addressed, ...channelMsgs].map(m => m._id);
      recent = await this._col.find({
        ...convFilter,
        _id: { $nin: excludeIds },
      }).sort({ timestamp: -1 }).limit(remaining).toArray();
      recent.reverse();
    }

    return { addressed, channel: channelMsgs, recent };
  }

  /**
   * Get the raw collection for direct queries.
   * @returns {import('mongodb').Collection}
   */
  get collection() {
    return this._col;
  }
}

module.exports = ConversationManager;
