const http = require('http');
const fs = require('fs');
const path = require('path');

const BASE = 'http://localhost:9200';
const API_KEY = fs.readFileSync(path.join(__dirname, '.api-key'), 'utf8').trim();
let pass = 0, fail = 0;

function test(name, opts, check) {
  return new Promise(resolve => {
    const url = new URL(opts.path, BASE);
    const req = http.request(url, { method: opts.method || 'GET', headers: opts.headers || {} }, res => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try {
          const ok = check(res, body);
          if (ok) { pass++; console.log(`✅ ${name}`); }
          else { fail++; console.log(`❌ ${name} (status=${res.statusCode})`); }
        } catch(e) { fail++; console.log(`❌ ${name}: ${e.message}`); }
        resolve();
      });
    });
    req.on('error', e => { fail++; console.log(`❌ ${name}: ${e.message}`); resolve(); });
    if (opts.body) { req.setHeader('Content-Type','application/json'); req.write(JSON.stringify(opts.body)); }
    req.end();
  });
}

async function run() {
  // --- Auth Tests ---
  await test('Health is public (no key needed)', { path: '/api/health' },
    (res) => res.statusCode === 200);

  await test('GET /api/tasks without key → 401', { path: '/api/tasks' },
    (res) => res.statusCode === 401);

  await test('GET /api/tasks with wrong key → 401', { path: '/api/tasks', headers: { 'X-API-Key': 'wrong-key' } },
    (res) => res.statusCode === 401);

  await test('GET /api/tasks with correct key (header) → 200', { path: '/api/tasks', headers: { 'X-API-Key': API_KEY } },
    (res, body) => res.statusCode === 200 && Array.isArray(JSON.parse(body)));

  await test('GET /api/tasks with correct key (query) → 200', { path: `/api/tasks?key=${API_KEY}` },
    (res, body) => res.statusCode === 200 && Array.isArray(JSON.parse(body)));

  await test('GET / without key → 401', { path: '/' },
    (res) => res.statusCode === 401);

  await test('GET / with key → 200 + dashboard', { path: `/?key=${API_KEY}` },
    (res, body) => res.statusCode === 200 && body.includes('Swarm Agent Dashboard'));

  await test('GET /api/stats with key → 200', { path: '/api/stats', headers: { 'X-API-Key': API_KEY } },
    (res, body) => { const d = JSON.parse(body); return 'passRate' in d && 'totalTasks' in d; });

  // --- Input Validation ---
  await test('POST /api/tasks without description → 400', {
    path: '/api/tasks', method: 'POST', headers: { 'X-API-Key': API_KEY },
    body: {}
  }, (res) => res.statusCode === 400);

  await test('POST /api/tasks with valid description → 201', {
    path: '/api/tasks', method: 'POST', headers: { 'X-API-Key': API_KEY },
    body: { description: 'Test task', agentId: 'koder' }
  }, (res, body) => { const d = JSON.parse(body); return res.statusCode === 201 && d.id; });

  await test('POST /api/tasks XSS sanitized', {
    path: '/api/tasks', method: 'POST', headers: { 'X-API-Key': API_KEY },
    body: { description: '<script>alert(1)</script>' }
  }, (res, body) => { const d = JSON.parse(body); return res.statusCode === 201 && !d.description.includes('<script>'); });

  await test('POST /api/tasks description too long → 400', {
    path: '/api/tasks', method: 'POST', headers: { 'X-API-Key': API_KEY },
    body: { description: 'x'.repeat(1001) }
  }, (res) => res.statusCode === 400);

  // --- Rate Limit Test ---
  // Send 101 requests rapidly, last should be 429
  let got429 = false;
  const promises = [];
  for (let i = 0; i < 105; i++) {
    promises.push(new Promise(resolve => {
      const req = http.request(new URL('/api/health', BASE), { method: 'GET' }, res => {
        if (res.statusCode === 429) got429 = true;
        res.resume();
        res.on('end', resolve);
      });
      req.on('error', resolve);
      req.end();
    }));
  }
  await Promise.all(promises);
  if (got429) { pass++; console.log('✅ Rate limiting works (got 429)'); }
  else { fail++; console.log('❌ Rate limiting: never got 429'); }

  console.log(`\n${pass}/${pass+fail} tests passed`);
  process.exit(fail > 0 ? 1 : 0);
}

run();
