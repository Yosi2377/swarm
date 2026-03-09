#!/usr/bin/env node
// Tests for Task Management API

const http = require('http');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const BASE = 'http://localhost:9200';
const API_KEY = '58ad0ba3378a306bf8023f28a853bcc0cddeb37d50a751e9f8e7f710c1c11e83';
const TASKS_DIR = '/tmp/agent-tasks';
const TEST_TASK_ID = 'tester-99999';

function req(method, urlPath, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlPath + (urlPath.includes("?") ? "&" : "?") + "key=" + API_KEY, BASE);
    const opts = { method, hostname: url.hostname, port: url.port, path: url.pathname + url.search, headers: {} };
    if (body) { const data = JSON.stringify(body); opts.headers['Content-Type'] = 'application/json'; opts.headers['Content-Length'] = Buffer.byteLength(data); }
    const r = http.request(opts, res => {
      let d = ''; res.on('data', c => d += c); res.on('end', () => {
        try { resolve({ status: res.statusCode, data: JSON.parse(d) }); } catch { resolve({ status: res.statusCode, data: d }); }
      });
    });
    r.on('error', reject);
    if (body) r.write(JSON.stringify(body));
    r.end();
  });
}

function cleanup() {
  const f = path.join(TASKS_DIR, `${TEST_TASK_ID}.json`);
  if (fs.existsSync(f)) fs.unlinkSync(f);
}

async function runTests() {
  let passed = 0, failed = 0;
  const test = async (name, fn) => {
    try { await fn(); console.log(`  ✅ ${name}`); passed++; }
    catch (e) { console.log(`  ❌ ${name}: ${e.message}`); failed++; }
  };

  console.log('\n🧪 Task Management API Tests\n');

  cleanup();

  // GET /api/tasks — list
  await test('GET /api/tasks returns tasks array', async () => {
    const r = await req('GET', '/api/tasks');
    assert.strictEqual(r.status, 200);
    assert(Array.isArray(r.data.tasks), 'tasks should be array');
    assert(typeof r.data.total === 'number', 'total should be number');
  });

  // POST /api/tasks — create
  await test('POST /api/tasks creates task', async () => {
    const r = await req('POST', '/api/tasks', { agent_id: 'tester', thread_id: '99999', task_desc: 'Test task from API tests', project: 'test' });
    assert.strictEqual(r.status, 201);
    assert.strictEqual(r.data.id, TEST_TASK_ID);
    assert.strictEqual(r.data.status, 'queued');
  });

  // POST duplicate
  await test('POST duplicate returns 409', async () => {
    const r = await req('POST', '/api/tasks', { agent_id: 'tester', thread_id: '99999', task_desc: 'dup' });
    assert.strictEqual(r.status, 409);
  });

  // POST missing fields
  await test('POST missing fields returns 400', async () => {
    const r = await req('POST', '/api/tasks', { agent_id: 'tester' });
    assert.strictEqual(r.status, 400);
  });

  // GET /api/tasks/:id
  await test('GET /api/tasks/:id returns task', async () => {
    const r = await req('GET', `/api/tasks/${TEST_TASK_ID}`);
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.data.id, TEST_TASK_ID);
    assert.strictEqual(r.data.agent_id, 'tester');
    assert.strictEqual(r.data.status, 'queued');
    assert(r.data.retryCount !== undefined);
    assert(r.data.maxRetries !== undefined);
  });

  // GET nonexistent
  await test('GET nonexistent returns 404', async () => {
    const r = await req('GET', '/api/tasks/nonexistent-999');
    assert.strictEqual(r.status, 404);
  });

  // POST retry
  await test('POST /api/tasks/:id/retry retries task', async () => {
    const r = await req('POST', `/api/tasks/${TEST_TASK_ID}/retry`);
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.data.status, 'running');
    assert.strictEqual(r.data.retryCount, 1);
  });

  // Verify state after retry
  await test('Task status is running after retry', async () => {
    const r = await req('GET', `/api/tasks/${TEST_TASK_ID}`);
    assert.strictEqual(r.data.status, 'running');
    assert.strictEqual(r.data.retryCount, 1);
  });

  // POST cancel
  await test('POST /api/tasks/:id/cancel cancels task', async () => {
    const r = await req('POST', `/api/tasks/${TEST_TASK_ID}/cancel`);
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.data.status, 'cancelled');
  });

  // Cannot retry cancelled
  // Actually per our code we CAN retry non-passed/non-cancelled... let's check cancel rejects double cancel
  await test('POST cancel on cancelled returns 400', async () => {
    const r = await req('POST', `/api/tasks/${TEST_TASK_ID}/cancel`);
    assert.strictEqual(r.status, 400);
  });

  // Filter by status
  await test('GET with status filter works', async () => {
    const r = await req('GET', '/api/tasks?status=cancelled');
    assert.strictEqual(r.status, 200);
    assert(r.data.tasks.some(t => t.id === TEST_TASK_ID));
  });

  // Filter by agent
  await test('GET with agent filter works', async () => {
    const r = await req('GET', '/api/tasks?agent=tester');
    assert.strictEqual(r.status, 200);
    assert(r.data.tasks.every(t => t.agent_id === 'tester'));
  });

  // Existing tasks from /tmp/agent-tasks
  await test('Lists existing tasks from /tmp/agent-tasks', async () => {
    const r = await req('GET', '/api/tasks');
    const ids = r.data.tasks.map(t => t.id);
    // koder-9821 and koder-6001 should exist
    assert(ids.includes('koder-9821'), 'Should include koder-9821');
  });

  // Dashboard page loads
  await test('GET /tasks.html returns HTML', async () => {
    const r = await req('GET', '/tasks.html');
    assert.strictEqual(r.status, 200);
  });

  cleanup();

  console.log(`\n📊 Results: ${passed} passed, ${failed} failed, ${passed + failed} total\n`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => { console.error('Test runner error:', e); process.exit(1); });
