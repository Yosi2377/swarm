#!/usr/bin/env node
/**
 * spawn-and-wait.js — Spawn a sub-agent via OpenClaw and wait for done marker
 * Usage: node spawn-and-wait.js <agentId> <threadId> <taskFile> <timeoutSeconds>
 */

const fs = require('fs');
const { execSync } = require('child_process');

const agentId = process.argv[2];
const threadId = process.argv[3];
const taskFile = process.argv[4];
const timeout = parseInt(process.argv[5] || '300');

const task = fs.readFileSync(taskFile, 'utf8');
const doneFile = `/tmp/agent-done/${agentId}-${threadId}.json`;

// Write a helper script that uses openclaw's session spawn
// We use exec to call back to the gateway
const spawnScript = `
const http = require('http');
const task = ${JSON.stringify(task)};

// Use the gateway's WebSocket API to spawn
// Since we can't easily use sessions_spawn from CLI,
// we'll write the task and let the orchestrator pick it up
const taskInfo = {
    agent: '${agentId}',
    thread: '${threadId}',
    task: task,
    spawned_at: new Date().toISOString()
};

require('fs').writeFileSync('/tmp/spawn-request-${agentId}-${threadId}.json', JSON.stringify(taskInfo, null, 2));
console.log('Spawn request written. Orchestrator should pick it up.');
`;

// Write spawn request for the orchestrator (main session) to pick up
fs.writeFileSync(`/tmp/spawn-request-${agentId}-${threadId}.json`, JSON.stringify({
    agent: agentId,
    thread: threadId,
    task: task,
    spawned_at: new Date().toISOString()
}, null, 2));

console.log(`Waiting for done marker: ${doneFile} (timeout: ${timeout}s)`);

// Poll for done marker
const startTime = Date.now();
const pollInterval = 5000; // 5 seconds

function checkDone() {
    if (fs.existsSync(doneFile)) {
        console.log('✅ Done marker found!');
        process.exit(0);
    }
    
    const elapsed = (Date.now() - startTime) / 1000;
    if (elapsed > timeout) {
        console.log(`⏰ Timeout after ${timeout}s`);
        process.exit(1);
    }
    
    setTimeout(checkDone, pollInterval);
}

checkDone();
