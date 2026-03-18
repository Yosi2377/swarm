# Agent Collaboration System — Design Doc
# Inspired by: let-them-talk (https://github.com/Dekelelz/let-them-talk)
# Target: TeamWork Swarm on Telegram

## Goal
Enable agents to truly collaborate — discuss, disagree, vote, give feedback — 
not just receive tasks and report back silently.

## Architecture

### Core: MongoDB collection `agent_conversations`
```js
{
  _id: ObjectId,
  conversation_id: String,    // e.g. "task-123" or "design-review-456"
  from: String,                // agent_id (koder, shomer, etc.)
  to: String,                  // agent_id or "__group__" 
  content: String,
  timestamp: Date,
  addressed_to: [String],      // who should respond
  reply_to: String,            // message _id for threading
  thread_id: String,           // conversation thread
  channel: String,             // "general", "code-review", "architecture"
  type: String,                // "message", "vote", "decision", "review"
  metadata: Object             // flexible per type
}
```

### Collection: `agent_decisions`
```js
{
  _id: ObjectId,
  conversation_id: String,
  topic: String,
  decision: String,
  decided_by: [String],        // agents who agreed
  votes: { agent_id: "for"|"against"|"abstain" },
  timestamp: Date,
  status: "proposed" | "voting" | "decided" | "overruled"
}
```

### Collection: `agent_reputation`
```js
{
  agent_id: String,
  score: Number,               // starts at 100
  history: [{
    event: String,             // "good_review", "task_completed", "bad_suggestion"
    delta: Number,
    timestamp: Date
  }]
}
```

## Key Modules

### 1. ConversationManager (conversation-manager.js)
Central module. Handles:
- `sendMessage(from, to, content, opts)` — with cooldown, budget, permissions
- `listenForMessages(agentId)` — returns batch with should_respond hints  
- `getContext(agentId)` — smart context: addressed msgs > channel msgs > recent
- Cooldown: adaptive per channel, fast lane for replies, slow for unsolicited
- Budget: max 2 unaddressed messages per 60s per agent
- Send-after-listen: must read before sending again

### 2. DecisionEngine (decision-engine.js)
- `proposeDecision(agentId, topic, proposal)`
- `vote(agentId, decisionId, vote, reason)`
- `getDecisions(conversationId)` — prevents re-debating
- Overlap detection: warn if message touches decided topic

### 3. ReviewSystem (review-system.js)
- `requestReview(fromAgent, code, context)`
- `submitReview(reviewerAgent, reviewId, approved, feedback)`
- Agents can disagree with reviews and escalate

### 4. ReputationTracker (reputation.js)
- Track quality of contributions
- Higher rep = suggestions weighted more in votes
- Decay over time if inactive

### 5. TelegramBridge (telegram-bridge.js)  
- Posts conversation highlights to Telegram topics
- Sends summaries, not every message (avoid spam)
- Key decisions, disagreements, and resolutions get posted

### 6. CollabPromptInjector (prompt-injector.js)
- Injects collaboration instructions into agent spawn prompts
- Teaches agents HOW to collaborate (when to respond, when to stay quiet)
- Adapts based on task type (debate vs execution vs review)

## Agent Behavior Rules (injected via prompt)
1. LISTEN before you speak — always check what others said
2. `should_respond: false` → stay quiet unless you have NEW info
3. Disagree constructively — state what and why, propose alternative
4. Don't repeat decided topics — check decisions first
5. Vote honestly — don't just agree with majority
6. Budget your messages — quality over quantity

## Integration with Existing Swarm
- dispatch-task.sh gets `--collab` flag for collaborative tasks
- Solo tasks (simple fixes) skip collaboration — direct dispatch
- Multi-agent tasks (architecture, design review) use full collab
- Orchestrator decides which mode based on task complexity

## Testing Plan
1. Unit tests: each module independently
2. Integration test: 3 agents debating an architecture decision
3. E2E test: full task with collaboration, voting, decision, execution
4. Stress test: 5+ agents, verify no spam/loops/deadlocks

## File Structure
```
/root/.openclaw/workspace/swarm/collab/
├── conversation-manager.js
├── decision-engine.js  
├── review-system.js
├── reputation.js
├── telegram-bridge.js
├── prompt-injector.js
├── test/
│   ├── unit-tests.js
│   ├── integration-test.js
│   └── e2e-test.js
├── templates/
│   ├── collab-prompt.md      # injected into agent prompts
│   ├── debate-prompt.md      # for debate-style tasks
│   └── review-prompt.md      # for code review tasks
└── package.json
```
