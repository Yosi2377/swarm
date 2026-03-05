# Swarm Upgrade Plan — Based on Research

## Phase 1: NOW — Core Reliability

### 1. Timeouts on ALL spawns
Every sessions_spawn MUST have runTimeoutSeconds (default 180)

### 2. Structured completion reports
Agents output JSON report, not free text

### 3. Verification pipeline  
Agent finishes → automated checks → evaluator → report

### 4. Smart timer (not fixed 90 sec)
Poll every 15 sec via subagents list, trigger eval when done

### 5. Failure handling
Timeout → retry once → escalate to orchestrator → report to user

## Phase 2: Quality
- Evaluator agent (bodek) reviews koder work
- Self-review step before completion
- Structured artifacts in swarm/artifacts/<task-id>/
- Better inter-agent communication via Agent Chat
