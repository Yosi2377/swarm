/**
 * @module ReviewSystem
 * Request code reviews, submit reviews with approve/reject/feedback,
 * and handle disagreement escalation.
 */

const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.COLLAB_DB || 'teamwork_collab';
const COLLECTION = 'agent_reviews';

/** Valid review statuses */
const REVIEW_STATUSES = ['pending', 'approved', 'rejected', 'changes_requested', 'escalated'];

class ReviewSystem {
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
    await this._col.createIndex({ requested_by: 1 });
    await this._col.createIndex({ status: 1 });
    return this;
  }

  async close() {
    if (this._client) await this._client.close();
  }

  /**
   * Request a code review.
   * @param {string} fromAgent - requesting agent
   * @param {string} code - code or file reference to review
   * @param {string} context - what the code does / why review needed
   * @param {Object} [opts]
   * @param {string[]} [opts.reviewers] - specific agents to review
   * @param {string} [opts.conversation_id]
   * @returns {Promise<{ok: boolean, review: Object}>}
   */
  async requestReview(fromAgent, code, context, opts = {}) {
    const doc = {
      requested_by: fromAgent,
      code,
      context,
      reviewers: opts.reviewers || [],
      conversation_id: opts.conversation_id || 'default',
      reviews: [],
      status: 'pending',
      created_at: new Date(),
      updated_at: new Date(),
    };

    const result = await this._col.insertOne(doc);
    doc._id = result.insertedId;
    return { ok: true, review: doc };
  }

  /**
   * Submit a review for a review request.
   * @param {string} reviewerAgent - reviewing agent
   * @param {string|ObjectId} reviewId - review request ID
   * @param {'approve'|'reject'|'feedback'} verdict
   * @param {string} feedback - review feedback text
   * @returns {Promise<{ok: boolean, review?: Object, error?: string, escalated?: boolean}>}
   */
  async submitReview(reviewerAgent, reviewId, verdict, feedback) {
    const validVerdicts = ['approve', 'reject', 'feedback'];
    if (!validVerdicts.includes(verdict)) {
      return { ok: false, error: `Invalid verdict "${verdict}". Must be: ${validVerdicts.join(', ')}` };
    }

    const id = typeof reviewId === 'string' ? new ObjectId(reviewId) : reviewId;
    const review = await this._col.findOne({ _id: id });
    if (!review) return { ok: false, error: 'Review not found' };

    const entry = {
      reviewer: reviewerAgent,
      verdict,
      feedback,
      timestamp: new Date(),
    };

    await this._col.updateOne({ _id: id }, {
      $push: { reviews: entry },
      $set: { updated_at: new Date() },
    });

    // Check for disagreements and auto-escalate
    const updated = await this._col.findOne({ _id: id });
    const escalated = this._checkDisagreement(updated);
    if (escalated) {
      await this._col.updateOne({ _id: id }, { $set: { status: 'escalated' } });
      updated.status = 'escalated';
    } else {
      // Update status based on latest verdict
      const newStatus = verdict === 'approve' ? 'approved'
        : verdict === 'reject' ? 'rejected'
        : 'changes_requested';
      await this._col.updateOne({ _id: id }, { $set: { status: newStatus } });
      updated.status = newStatus;
    }

    return { ok: true, review: updated, escalated };
  }

  /**
   * Get pending reviews for an agent (as reviewer).
   * @param {string} agentId
   * @returns {Promise<Object[]>}
   */
  async getPendingReviews(agentId) {
    return this._col.find({
      $or: [
        { reviewers: agentId, status: 'pending' },
        { reviewers: { $size: 0 }, status: 'pending' }, // open reviews
      ],
    }).sort({ created_at: -1 }).toArray();
  }

  /**
   * Get all reviews for a conversation.
   * @param {string} conversationId
   * @returns {Promise<Object[]>}
   */
  async getReviews(conversationId) {
    return this._col.find({ conversation_id: conversationId }).sort({ created_at: -1 }).toArray();
  }

  /**
   * Check for disagreement among reviewers (approve vs reject).
   * If found, review should be escalated.
   * @param {Object} review
   * @returns {boolean}
   */
  _checkDisagreement(review) {
    const verdicts = (review.reviews || []).map(r => r.verdict);
    const hasApprove = verdicts.includes('approve');
    const hasReject = verdicts.includes('reject');
    return hasApprove && hasReject;
  }

  get collection() { return this._col; }
}

module.exports = ReviewSystem;
